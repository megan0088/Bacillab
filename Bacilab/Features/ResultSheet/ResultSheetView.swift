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

    private var gradeColor: Color {
        switch grade {
        case .negative:              return .green
        case .scanty:                return .orange
        case .plus1, .plus2, .plus3: return .red
        }
    }

    private var gradeLabel: String {
        switch grade {
        case .negative: return "Negative"
        case .scanty:   return "Scanty"
        case .plus1:    return "Positive (1+)"
        case .plus2:    return "Positive (2+)"
        case .plus3:    return "Positive (3+)"
        }
    }

    /// The WHO/IUATLD criterion for this band — a definition, not a report of what was seen.
    private var gradeCriterion: String {
        switch grade {
        case .negative: return "No BTA in 100 fields of view"
        case .scanty:   return "1–9 BTA in 100 fields of view; repeat examination advised"
        case .plus1:    return "10–99 BTA in 100 fields of view"
        case .plus2:    return "1–10 BTA per field across at least 50 fields"
        case .plus3:    return "More than 10 BTA per field across at least 20 fields"
        }
    }

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
    }

    // MARK: - Patient

    private var patientCard: some View {
        card {
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
        card {
            sectionHeading("Result", tinted: true)

            Label("AI analysis ≠ Medical diagnosis", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)

            gradeBox

            infoRow("Total Fields Read", "\(session.examinedFieldCount)")
            infoRow("Total BTA Detected", "\(session.totalBTA)")
            infoRow("AI Confidence",
                    meanConfidence.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")

            if !session.isGradeConfirmed {
                Label(
                    "Only \(session.examinedFieldCount) fields read. \(grade.rawValue) requires "
                    + "\(grade.minimumFields) fields (WHO/IUATLD), so this result is not final.",
                    systemImage: "exclamationmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The grade, and a chevron that opens how it was reached.
    ///
    /// The chevron expands an explanation; it is not a picker. A grade chosen here would put
    /// grade-setting on a second screen, which is precisely what Review exists to own alone.
    private var gradeBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.22)) { isGradeExpanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(gradeLabel)
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(gradeColor)

                            if !session.isGradeConfirmed {
                                Text("PROVISIONAL")
                                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.orange.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.orange)
                            }
                        }
                        Text(gradeCriterion)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.headline)
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

    /// How the grade was arrived at.
    ///
    /// A grade is an **extrapolation**: bacilli counted across the fields actually read, scaled
    /// to 100 fields, landing in a band. "2+" does not mean two of anything. Without this the
    /// reader has to take the letter on trust, and the one number that matters clinically is the
    /// one they cannot check.
    @ViewBuilder
    private var gradeDerivation: some View {
        let fields = max(session.examinedFieldCount, 1)
        let per100 = Double(session.totalBTA) / Double(fields) * 100

        VStack(alignment: .leading, spacing: 6) {
            Divider()

            derivationRow("Counted",
                          "\(session.totalBTA) BTA across \(session.examinedFieldCount) fields read")
            derivationRow("Extrapolated", String(format: "%.0f BTA per 100 fields", per100))
            derivationRow("Fields required",
                          session.isGradeConfirmed
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
                .font(.caption2.weight(.semibold))
                .frame(width: 108, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Notes

    private var notesCard: some View {
        card {
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

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func sectionHeading(_ title: String, tinted: Bool) -> some View {
        Text(title)
            .font(.system(.headline, design: .rounded, weight: .bold))
            .foregroundStyle(tinted ? Color.accentColor : .primary)
    }

    /// Label on the left, value on the right — the shape a printed lab report uses.
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 12)
            Text(value.isEmpty ? "—" : value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
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
