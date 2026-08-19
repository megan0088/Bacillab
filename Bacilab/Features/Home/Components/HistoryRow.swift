import SwiftUI

struct HistoryRow: View {
    let session: ExamSession

    var body: some View {
        let badge = SessionBadge(session: session)

        return HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "doc.text.fill")
                        .font(.appHeading)
                        .foregroundStyle(Color.accentColor)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(session.patient.examinationDate.formatted(.dateTime.day().month(.wide).year()))
                    .font(.appCaption)
                    .foregroundStyle(.secondary)

                // The record number leads: it is what is written on the tube and the form, and
                // is often the only thing the technician is holding when they come looking.
                Text(session.patient.medicalRecordNumber.isEmpty
                     ? "No MRN" : session.patient.medicalRecordNumber)
                    .font(.appBody.weight(.semibold))

                Text(session.patient.name.isEmpty ? "Unnamed" : session.patient.name)
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Badge(text: badge.text, tint: badge.tint)
                .fixedSize()

            Image(systemName: "chevron.right")
                .font(.appCaption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview("HistoryRow") {
    let session = ExamSession()
    session.patient.name = "Ahmad Rizki"
    session.patient.medicalRecordNumber = "RM 240724-001"
    return HistoryRow(session: session)
        .padding()
        .background(.black)
}
