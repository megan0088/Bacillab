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
                    ReviewHeader(viewModel: viewModel)
                }

                FieldPager(
                    fields: session.fields,
                    selectedID: viewModel.selectedField?.id,
                    onSelect: { viewModel.select($0) }
                )

                fieldCanvas
                detectorLegend
                FieldCountRow(viewModel: viewModel, onEdit: { viewModel.openKeypad() })
                fieldActions

                Divider().padding(.vertical, 4)

                totalsSection
                GradePicker(session: session, viewModel: viewModel, onContinueScanning: {
                    session.status = .scanning
                    dismiss()
                })
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

    /// Shown only once a field has been read: before that there is nothing to name.
    @ViewBuilder
    private var detectorLegend: some View {
        if let analysis = viewModel.selectedField?.analysis, !analysis.readings.isEmpty {
            DetectorLegend(readings: analysis.readings, primary: analysis.primary)
                .padding(.horizontal, 20)
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
            statCell(label: "Model Suggests", value: session.suggestedGrade.displayName)
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
