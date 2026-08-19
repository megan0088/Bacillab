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

    @State private var isGradeExpanded = false

    private var grade: BTAGrade { session.reportedGrade }

    private var gradeColor: Color { grade.tint }

    private var gradeLabel: String { grade.displayName }

    private var gradeCriterion: String { grade.criterion }

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
                patientCard
                resultCard
                notesCard
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

    // MARK: - Patient

    private var patientCard: some View {
        Card {
            sectionHeading("Patient Information", tinted: true)

            infoRow("MRN", session.patient.medicalRecordNumber)
            infoRow("NIK", session.patient.nationalID)
            infoRow("Name", session.patient.name)
            infoRow("DOB", formatted(session.patient.dateOfBirth))
            infoRow("Examination Date", formatted(session.patient.examinationDate))
        }
    }

    // MARK: - Result

    private var resultCard: some View {
        Card {
            sectionHeading("Result", tinted: true)

            Label("AI analysis ≠ Medical diagnosis", systemImage: "exclamationmark.triangle.fill")
                .font(.appCaption)
                .foregroundStyle(.orange)

            gradeBox

            infoRow("Total Fields Read", "\(session.examinedFieldCount)")
            infoRow("Total BTA Detected", "\(session.totalBTA)")
            infoRow("AI Confidence",
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

    /// The grade, and a chevron that opens the scale so the lab can re-decide it.
    ///
    /// The counts are frozen at publication and cannot be touched here; the grade is not. A lab
    /// technician revising an extrapolated grade is ordinary practice, and this is where they do
    /// it. What matters is that the field-count gate follows whatever they pick — choosing
    /// Negative on 20 fields immediately stamps PROVISIONAL and says how many fields short it
    /// is, so re-deciding can never be a way to make a provisional reading look final.
    private var gradeBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.22)) { isGradeExpanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(gradeLabel)
                                .font(.appTitle.weight(.bold))
                                .foregroundStyle(gradeColor)

                            if !session.isGradeConfirmed, !DemoMode.hidesProvisionalMarks {
                                Text("PROVISIONAL")
                                    .font(.appCaption.weight(.heavy))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.orange.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.orange)
                            }
                        }
                        Text(gradeCriterion)
                            .font(.appCaption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.appBody.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isGradeExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            if isGradeExpanded { gradeDerivation }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray4), lineWidth: 1))
    }

    /// The whole WHO/IUATLD scale, with this result's band marked.
    ///
    /// Shows where the reading sits among the five, so a reader can see what would have had to
    /// be true for it to land anywhere else — and, underneath, how this one was actually reached.
    /// A grade is an **extrapolation**: bacilli counted across the fields read, scaled to 100
    /// fields, landing in a band. "2+" does not mean two of anything.
    @ViewBuilder
    private var gradeDerivation: some View {
        let fields = max(session.examinedFieldCount, 1)
        let per100 = Double(session.totalBTA) / Double(fields) * 100

        VStack(alignment: .leading, spacing: 0) {
            ForEach(BTAGrade.allCases, id: \.self) { band in
                Divider().padding(.vertical, 10)

                Button {
                    session.chooseGrade(band)
                    persist()
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(band.displayName)
                                .font(.appBody.weight(.bold))
                                .foregroundStyle(band == grade ? gradeColor : .primary)
                            Text(band.criterion)
                                .font(.appCaption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: band == grade ? "checkmark.circle.fill" : "circle")
                            .font(.appBody)
                            .foregroundStyle(band == grade ? gradeColor : Color(.systemGray3))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Divider().padding(.vertical, 10)

            derivationRow("Counted",
                          "\(session.totalBTA) BTA across \(session.examinedFieldCount) fields read")
            derivationRow("Extrapolated", String(format: "%.0f BTA per 100 fields", per100))
            // The requirement itself always shows — it is what the scale is built on. Only the
            // met/short verdict is a provisional mark, so only that part answers to the flag.
            derivationRow("Fields required",
                          DemoMode.hidesProvisionalMarks
                          ? "\(grade.minimumFields) (WHO/IUATLD)"
                          : session.isGradeConfirmed
                          ? "\(grade.minimumFields) (WHO/IUATLD) — met"
                          : "\(grade.minimumFields) (WHO/IUATLD) — \(session.fieldsRemainingForGrade) short")
            // Two models read every field but only one produces this number, and a reader has no
            // other way to know which.
            derivationRow("Counted by", "ResNet. YOLO11 read the same fields for comparison only.")

            // A slide read partly through the eyepiece and partly from imported photos is two
            // acquisitions pooled into one grade. Silent about it, this sheet would imply one.
            if session.importedFieldCount > 0 {
                derivationRow("Imported fields",
                              "\(session.importedFieldCount) of \(session.examinedFieldCount) came from photos, not the eyepiece")
            }
        }
    }

    private func derivationRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.appCaption.weight(.semibold))
                .frame(width: 108, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.appCaption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Notes

    private var notesCard: some View {
        Card {
            sectionHeading("Notes by Medical Laboratory", tinted: false)

            TextEditor(text: $session.notes)
                .frame(minHeight: 90)
                .scrollContentBackground(.hidden)
                .padding(8)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray4), lineWidth: 1))
                .overlay(alignment: .topLeading) {
                    if session.notes.isEmpty {
                        Text("Enter notes (optional)...")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 16)
                            .padding(.leading, 13)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    // MARK: - Building blocks

    private func sectionHeading(_ title: String, tinted: Bool) -> some View {
        Text(title)
            .font(.appBody.weight(.bold))
            .foregroundStyle(tinted ? Color.accentColor : .primary)
    }

    /// Label on the left, value on the right — the shape a printed lab report uses.
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.appBody.weight(.semibold))
            Spacer(minLength: 12)
            Text(value.isEmpty ? "—" : value)
                .font(.appBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    /// Writes the session back after the lab changes something here.
    ///
    /// Only the grade and the notes can reach this — the counts were frozen when the result was
    /// published, and nothing on this screen can move them.
    private func persist() {
        Task {
            try? await dependencies.sessionStore.save(session.snapshot())
        }
    }

    private func formatted(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year())
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
