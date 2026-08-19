import SwiftUI

/// The patient identity block at the top of the result sheet.
///
/// Takes `PatientInfo` rather than the whole session because it reads nothing else — the
/// narrower input is what keeps it obviously read-only.
struct PatientSection: View {
    let patient: PatientInfo

    var body: some View {
        Card {
            SectionHeader("Patient Information", tinted: true)

            InfoRow("MRN", patient.medicalRecordNumber)
            InfoRow("NIK", patient.nationalID)
            InfoRow("Name", patient.name)
            InfoRow("DOB", formatted(patient.dateOfBirth))
            InfoRow("Examination Date", formatted(patient.examinationDate))
        }
    }

    private func formatted(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year())
    }
}

#Preview("Patient Information") {
    var patient = PatientInfo()
    patient.name = "Andreas Simbolon"
    patient.medicalRecordNumber = "RM 240724-001"
    patient.nationalID = "3204012509900001"
    return PatientSection(patient: patient)
        .padding()
        .background(Color(.systemGroupedBackground))
}
