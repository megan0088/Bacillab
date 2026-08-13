import SwiftUI

/// Satu-satunya layar yang memutuskan.
///
/// Di sini analis memeriksa tiap lapang, mengoreksi hitungannya, membuang lapang yang tidak
/// layak, memilih grade, dan menerbitkan hasil. Sesi scan tidak punya satu pun dari itu.
struct ReviewView: View {
    @State private var viewModel: ReviewViewModel
    let dependencies: AppDependencies

    @Environment(\.dismiss) private var dismiss
    @State private var goToResult = false
    @State private var showUnresolvedWarning = false

    init(session: ExamSession, queue: FieldAnalysisQueue, dependencies: AppDependencies) {
        self.dependencies = dependencies
        _viewModel = State(initialValue: ReviewViewModel(
            session: session,
            store: dependencies.sessionStore,
            queue: queue
        ))
    }

    private var session: ExamSession { viewModel.session }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if viewModel.queue.remaining > 0 {
                    analysisProgress
                }

                FieldPager(
                    fields: session.fields,
                    selectedID: viewModel.selectedField?.id,
                    onSelect: { viewModel.select($0) }
                )

                fieldCanvas
                fieldCountRow
                fieldActions

                Divider().padding(.vertical, 4)

                totalsSection
                gradeSection
                notesSection
                publishButton
            }
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $goToResult) {
            ResultSheetView(session: session, dependencies: dependencies)
        }
        .sheet(isPresented: $viewModel.isKeypadPresented) {
            CountKeypad(
                text: viewModel.keypadText,
                onDigit: { viewModel.appendDigit($0) },
                onDelete: { viewModel.deleteDigit() },
                onConfirm: { viewModel.commitKeypad() },
                onCancel: { viewModel.cancelKeypad() }
            )
            .presentationDetents([.medium])
        }
        .alert("Masih ada lapang tanpa hitungan", isPresented: $showUnresolvedWarning) {
            Button("Terbitkan Saja", role: .destructive) { publish() }
            Button("Periksa Dulu", role: .cancel) {}
        } message: {
            Text("\(viewModel.unresolvedFields.count) lapang belum punya angka dan tidak ikut "
                 + "dihitung — baik pembilang maupun penyebutnya. Isi lewat keypad, atau buang "
                 + "lapangnya, supaya hasilnya mewakili apa yang benar-benar dibaca.")
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Antrean

    private var analysisProgress: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Menganalisis \(session.fields.count - viewModel.queue.remaining) "
                 + "dari \(session.fields.count) lapang…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
    }

    // MARK: - Lapang terpilih

    private var fieldCanvas: some View {
        GeometryReader { geo in
            let side = min(geo.size.width - 40, 320)
            HStack {
                Spacer()
                FieldCanvas(
                    image: viewModel.selectedField.flatMap { field in
                        viewModel.imageData(for: field).flatMap(UIImage.init(data:))
                    },
                    readings: viewModel.selectedField?.analysis?.readings ?? [],
                    side: side
                )
                Spacer()
            }
        }
        .frame(height: 320)
    }

    private var fieldCountRow: some View {
        VStack(spacing: 8) {
            Button {
                viewModel.openKeypad()
            } label: {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(countLabel)
                        .font(.system(size: 46, weight: .black, design: .rounded))
                        .contentTransition(.numericText())
                    Text("BTA")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(.secondary)
                    Image(systemName: "pencil.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .foregroundStyle(.primary)

            confidenceLine
        }
    }

    private var countLabel: String {
        guard let field = viewModel.selectedField else { return "—" }
        if field.isExcluded { return "—" }
        guard let count = field.effectiveCount else { return "—" }
        return "\(count)"
    }

    /// Confidence ditampilkan sebagai milik model, bukan sebagai kepastian hasil.
    ///
    /// Grafik ONNX sudah membuang deteksi di bawah 0,70, jadi angka ini tidak pernah bisa
    /// terbaca di bawah 70% betapapun lemahnya sebuah lapang. Ia menyatakan seberapa yakin
    /// model terhadap basil yang **ia simpan** — bukan seberapa yakin siapa pun terhadap
    /// hitungannya.
    @ViewBuilder
    private var confidenceLine: some View {
        if let field = viewModel.selectedField {
            if field.correctedCount != nil {
                Label("Dikoreksi analis", systemImage: "hand.raised.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            } else if field.analysis == nil {
                Text("Menunggu analisis…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if field.effectiveCount == nil {
                Label("Model gagal membaca lapang ini — isi manual",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if let confidence = field.analysis?.confidence {
                Text("Model yakin \(Int((confidence * 100).rounded()))% atas basil yang ia tandai")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var fieldActions: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.selectPrevious()
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 40)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
            }
            .disabled(viewModel.selectedIndex == 0)

            Button {
                viewModel.toggleExcludedOnSelected()
            } label: {
                Label(
                    viewModel.selectedField?.isExcluded == true ? "Pakai Lagi" : "Buang Lapang",
                    systemImage: viewModel.selectedField?.isExcluded == true
                        ? "arrow.uturn.backward" : "trash"
                )
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
            }
            .foregroundStyle(viewModel.selectedField?.isExcluded == true ? Color.accentColor : .red)

            Button {
                viewModel.selectNext()
            } label: {
                Text("Simpan & Lanjut")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
            }
            .disabled(viewModel.selectedIndex >= session.fields.count - 1)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Total

    private var totalsSection: some View {
        HStack(spacing: 0) {
            statCell(label: "Lapang Terbaca", value: "\(session.examinedFieldCount)")
            Divider().frame(height: 44)
            statCell(label: "Total BTA", value: "\(session.totalBTA)")
            Divider().frame(height: 44)
            statCell(label: "Usulan Model", value: session.suggestedGrade.rawValue)
        }
        .padding(.vertical, 14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Grade

    private var gradeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tentukan Grade")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BTAGrade.allCases, id: \.self) { grade in
                        Button {
                            viewModel.chooseGrade(grade)
                        } label: {
                            Text(grade.rawValue)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 9)
                                .background(session.reportedGrade == grade
                                            ? Color.accentColor : Color(.systemGray5),
                                            in: Capsule())
                                .foregroundStyle(session.reportedGrade == grade ? .white : .primary)
                        }
                    }
                }
            }

            if !session.isGradeConfirmed {
                provisionalNotice
            }
        }
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
    }

    /// Di bawah ambang WHO/IUATLD grade ini belum boleh berdiri sebagai laporan.
    private var provisionalNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                "\(session.reportedGrade.rawValue) memerlukan \(session.reportedGrade.minimumFields) "
                + "lapang (WHO/IUATLD). Kurang \(session.fieldsRemainingForGrade) lapang lagi — "
                + "hasil akan bercap SEMENTARA.",
                systemImage: "exclamationmark.circle.fill"
            )
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)

            Button {
                session.status = .scanning
                dismiss()
            } label: {
                Label("Lanjut Scan", systemImage: "camera.fill")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    // MARK: - Catatan

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Catatan Laboratorium")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))

            TextEditor(text: Bindable(session).notes)
                .frame(minHeight: 90)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray4), lineWidth: 1))
        }
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
    }

    // MARK: - Terbit

    private var publishButton: some View {
        Button {
            if viewModel.unresolvedFields.isEmpty {
                publish()
            } else {
                showUnresolvedWarning = true
            }
        } label: {
            HStack {
                if viewModel.isPublishing { ProgressView().tint(.white) }
                Text("Terbitkan Hasil")
                    .font(.system(.body, design: .rounded, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
        }
        .disabled(viewModel.isPublishing || session.fields.isEmpty)
        .padding(.horizontal, 20)
        .padding(.bottom, 32)
    }

    private func publish() {
        Task {
            await viewModel.publish()
            if viewModel.isPublished { goToResult = true }
        }
    }
}

#Preview("Review – 6 lapang") {
    let session = ExamSession()
    session.patient.name = "Ahmad Rizki"
    session.patient.medicalRecordNumber = "RM 240724-001"
    for i in 0..<6 {
        let f = session.appendField(imageFileName: "f.jpg")
        session.setAnalysis(FieldAnalysis(
            readings: [DetectorReading(detector: .resnet, btaCount: i * 2,
                                       confidence: 0.86, elapsed: 0.6)],
            primary: .resnet), for: f.id)
    }
    let deps = AppDependencies()
    return NavigationStack {
        ReviewView(session: session, queue: deps.makeAnalysisQueue(), dependencies: deps)
    }
}
