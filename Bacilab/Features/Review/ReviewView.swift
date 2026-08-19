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
        .background(Color.black)
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.large)
        // Dark, like the capture screens either side of it: the analyst moves between them in a
        // dim room and a white sheet between two black ones is the thing that hurts.
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
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
        .alert("Some fields have no count", isPresented: $showUnresolvedWarning) {
            Button("Publish Anyway", role: .destructive) { publish() }
            Button("Check First", role: .cancel) {}
        } message: {
            Text("\(viewModel.unresolvedFields.count) fields have no number yet and count "
                 + "towards neither the total nor the denominator. Enter them on the keypad, or "
                 + "discard them, so the result reflects what was actually read.")
        }
        .alert("Something went wrong", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        // Picks up fields the queue never got to — a session resumed after the app was killed,
        // or a seeded one that arrived unanalysed.
        .task { viewModel.analysePendingFields() }
    }

    // MARK: - Queue

    private var analysisProgress: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Analysing \(session.fields.count - viewModel.queue.remaining) "
                 + "of \(session.fields.count) fields…")
                .font(.appCaption)
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
                    image: viewModel.selectedField.flatMap { viewModel.image(for: $0) },
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
                HStack(spacing: 10) {
                    Text(countLabel)
                        .font(.appHeading.weight(.bold))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("BTA")
                        .font(.appBody.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.5))
                    Image(systemName: "pencil")
                        .font(.appCaption)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(.white.opacity(0.25), lineWidth: 1))
            }
            .foregroundStyle(.primary)

            confidenceLine
        }
    }

    /// Below this the field is flagged for a manual look. **Not calibrated** against read slides.
    private static let lowConfidencePercent = 85

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
                Label("Corrected by analyst", systemImage: "hand.raised.fill")
                    .font(.appCaption)
                    .foregroundStyle(Color.accentColor)
            } else if field.analysis == nil {
                Text("Waiting for analysis…")
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
            } else if field.effectiveCount == nil {
                Label("The model could not read this field — enter it manually",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.appCaption)
                    .foregroundStyle(.orange)
            } else if let confidence = field.analysis?.confidence {
                let percent = Int((confidence * 100).rounded())
                VStack(spacing: 4) {
                    Text("\(percent)% AI Confidence Level")
                        .font(.appCaption)
                        .foregroundStyle(.white.opacity(0.55))

                    // Prompts a second look; it never changes a count. The threshold is a
                    // starting point, not a calibrated one — and note the graph already discards
                    // detections below 0.70, so this figure can never read lower than 70% however
                    // weak the field is. It says how sure the model is about the bacilli it kept.
                    if percent < Self.lowConfidencePercent {
                        Label("Low AI Confidence, Verify Manually",
                              systemImage: "exclamationmark.circle.fill")
                            .font(.appCaption)
                            .foregroundStyle(.orange)
                    }
                }
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
                    viewModel.selectedField?.isExcluded == true ? "Use Again" : "Discard Field",
                    systemImage: viewModel.selectedField?.isExcluded == true
                        ? "arrow.uturn.backward" : "trash"
                )
                .font(.appCaption.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
            }
            .foregroundStyle(viewModel.selectedField?.isExcluded == true ? Color.accentColor : .red)

            Button {
                viewModel.selectNext()
            } label: {
                Text("Sure & Continue")
                    .font(.appBody.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            .disabled(viewModel.selectedIndex >= session.fields.count - 1)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Total

    private var totalsSection: some View {
        HStack(spacing: 0) {
            statCell(label: "Fields Read", value: "\(session.examinedFieldCount)")
            Divider().frame(height: 44)
            statCell(label: "Total BTA", value: "\(session.totalBTA)")
            Divider().frame(height: 44)
            statCell(label: "Model Suggests", value: session.suggestedGrade.rawValue)
        }
        .padding(.vertical, 14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.appBody.weight(.bold))
                .contentTransition(.numericText())
            Text(label)
                .font(.appCaption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Grade

    private var gradeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Set Grade")
                .font(.appBody.weight(.semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BTAGrade.allCases, id: \.self) { grade in
                        Button {
                            viewModel.chooseGrade(grade)
                        } label: {
                            Text(grade.rawValue)
                                .font(.appCaption.weight(.semibold))
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

    /// Below the WHO/IUATLD threshold this grade may not stand as a report.
    private var provisionalNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Only the warning is suppressed for the exhibition. `Continue Scanning` below stays
            // either way — hiding the shortfall *and* the way to fix it would leave the analyst
            // no route to a grade that is actually confirmed.
            if !DemoMode.hidesProvisionalMarks {
                Label(
                    "\(session.reportedGrade.rawValue) needs \(session.reportedGrade.minimumFields) "
                    + "fields (WHO/IUATLD). \(session.fieldsRemainingForGrade) more to go — "
                    + "the result will be stamped PROVISIONAL.",
                    systemImage: "exclamationmark.circle.fill"
                )
                .font(.appCaption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                session.status = .scanning
                dismiss()
            } label: {
                Label("Continue Scanning", systemImage: "camera.fill")
                    .font(.appCaption.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    // MARK: - Catatan

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Laboratory Notes")
                .font(.appBody.weight(.semibold))

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
                Text("Publish Result")
                    .font(.appBody.weight(.semibold))
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
        ReviewView(session: session, queue: deps.queue(for: session), dependencies: deps)
    }
}
