import SwiftUI

/// The published result sheet.
///
/// The grade, the per-field counts and which fields were discarded were all decided in Review.
/// Nothing here can change any of them — a second screen that could set a grade is the collision
/// this redesign removed. Lab notes are the one exception, and deliberately so: a comment is
/// often added after a result has been read, and it is not part of the reading.
///
/// This is also the screen reached by tapping an examination in history, so it is the same view
/// in both places rather than a sibling that could drift.
struct ResultSheetView: View {
    @Bindable var session: ExamSession
    let dependencies: AppDependencies

    private var grade: BTAGrade { session.reportedGrade }

    /// Mean confidence over the fields that actually contributed a count.
    ///
    /// Fields the model read as empty carry no confidence — there is nothing to be confident
    /// about — so they are left out rather than averaged in as zero.
    private var meanConfidence: Double? {
        let values = session.countedFields.compactMap { $0.analysis?.confidence }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PatientSection(patient: session.patient)
                resultCard
                NotesSection(session: session)
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Interpretation")
        .navigationBarTitleDisplayMode(.large)
        // Notes are saved on the way out rather than per keystroke: the manifest is rewritten
        // whole each time, and a write per character would be pure churn.
        .onDisappear { persist() }
    }

    // MARK: - Result

    private var resultCard: some View {
        Card {
            SectionHeader("Result", tinted: true)

            Label("AI analysis ≠ Medical diagnosis", systemImage: "exclamationmark.triangle.fill")
                .font(.appCaption)
                .foregroundStyle(.orange)

            GradeBox(session: session, onGradeChange: persist)

            InfoRow("Total Fields Read", "\(session.examinedFieldCount)")
            InfoRow("Total BTA Detected", "\(session.totalBTA)")
            InfoRow("AI Confidence",
                    meanConfidence.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")

            if !session.isGradeConfirmed, !DemoMode.hidesProvisionalMarks {
                Label(
                    "Only \(session.examinedFieldCount) fields read. \(grade.displayName) requires "
                    + "\(grade.minimumFields) fields (WHO/IUATLD), so this result is not final.",
                    systemImage: "exclamationmark.circle.fill"
                )
                .font(.appCaption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Building blocks

    /// Writes the session back after the lab changes something here.
    ///
    /// Only the grade and the notes can reach this — the counts were frozen when the result was
    /// published, and nothing on this screen can move them.
    private func persist() {
        Task {
            try? await dependencies.sessionStore.save(session.snapshot())
        }
    }
}

#Preview("Interpretation – 2+ confirmed") {
    let session = ExamSession()
    session.patient.name = "Andreas Simbolon"
    session.patient.medicalRecordNumber = "RM 240724-001"
    session.patient.nationalID = "3204012509900001"
    session.status = .published
    for _ in 0..<50 {
        let f = session.appendField(imageFileName: "f.jpg")
        session.setAnalysis(FieldAnalysis(
            readings: [DetectorReading(detector: .resnet, btaCount: 3,
                                       confidence: 0.98, elapsed: 0.6)],
            primary: .resnet), for: f.id)
    }
    return NavigationStack {
        ResultSheetView(session: session, dependencies: AppDependencies())
    }
}

#Preview("Interpretation – Negative, provisional") {
    let session = ExamSession()
    session.patient.name = "Siti Rahma"
    session.patient.medicalRecordNumber = "RM 240724-002"
    session.status = .published
    for _ in 0..<20 {
        let f = session.appendField(imageFileName: "f.jpg")
        session.setAnalysis(FieldAnalysis(
            readings: [DetectorReading(detector: .resnet, btaCount: 0,
                                       confidence: 0, elapsed: 0.6)],
            primary: .resnet), for: f.id)
    }
    return NavigationStack {
        ResultSheetView(session: session, dependencies: AppDependencies())
    }
}
