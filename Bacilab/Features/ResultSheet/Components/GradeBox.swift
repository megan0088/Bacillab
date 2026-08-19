import SwiftUI

/// The grade, and a chevron that opens the scale so the lab can re-decide it.
///
/// The counts are frozen at publication and cannot be touched here; the grade is not. A lab
/// technician revising an extrapolated grade is ordinary practice, and this is where they do
/// it. What matters is that the field-count gate follows whatever they pick — choosing
/// Negative on 20 fields immediately stamps PROVISIONAL and says how many fields short it
/// is, so re-deciding can never be a way to make a provisional reading look final.
struct GradeBox: View {
    @Bindable var session: ExamSession

    @State private var isExpanded = false

    private var grade: BTAGrade { session.reportedGrade }

    private var gradeColor: Color { grade.tint }

    private var gradeLabel: String { grade.displayName }

    private var gradeCriterion: String { grade.criterion }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.22)) { isExpanded.toggle() }
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
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            if isExpanded { gradeDerivation }
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
}

#Preview("GradeBox – confirmed") {
    let session = ExamSession()
    for _ in 0..<50 {
        let f = session.appendField(imageFileName: "f.jpg")
        session.setAnalysis(FieldAnalysis(
            readings: [DetectorReading(detector: .resnet, btaCount: 3,
                                       confidence: 0.98, elapsed: 0.6)],
            primary: .resnet), for: f.id)
    }
    return GradeBox(session: session)
        .padding()
        .background(Color(.systemGroupedBackground))
}

#Preview("GradeBox – below the field gate") {
    let session = ExamSession()
    for _ in 0..<20 {
        let f = session.appendField(imageFileName: "f.jpg")
        session.setAnalysis(FieldAnalysis(
            readings: [DetectorReading(detector: .resnet, btaCount: 0,
                                       confidence: 0, elapsed: 0.6)],
            primary: .resnet), for: f.id)
    }
    return GradeBox(session: session)
        .padding()
        .background(Color(.systemGroupedBackground))
}
