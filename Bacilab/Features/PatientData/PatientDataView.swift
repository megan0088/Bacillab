import SwiftUI

/// Patient and sample details, captured before the scan session starts.
///
/// Dependencies arrive as an explicit `let`, not `@Environment`: this view is pushed inside a
/// sheet's `NavigationStack`, where `@Environment(AppDependencies.self)` crashes at runtime.
struct PatientDataView: View {
    @Bindable var session: ExamSession
    let dependencies: AppDependencies
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Field names sit in the placeholder rather than on a label above, matching the
                // hi-fi. The grouping is corrected, though: the design file placed Patient Name
                // under "Test Information", which is not where anyone would look for it.
                SectionHeader("Patient Information", tinted: true)

                LabeledField(placeholder: "Medical Record Number (MRN)",
                             text: $session.patient.medicalRecordNumber)
                LabeledField(placeholder: "NIK", text: $session.patient.nationalID)
                LabeledField(placeholder: "Patient Name", text: $session.patient.name)
                LabeledDateField(label: "Date of Birth", date: $session.patient.dateOfBirth)
                LabeledField(placeholder: "Address", text: $session.patient.address)
                LabeledField(placeholder: "Phone Number", text: $session.patient.phone)

                SectionHeader("Test Information", tinted: true)

                LabeledDateField(label: "Examination Date", date: $session.patient.examinationDate)
                LabeledDateField(label: "Sample Collection Time",
                                 date: $session.patient.sampleCollectedAt,
                                 components: [.date, .hourAndMinute])

                Spacer(minLength: 24)

                NavigationLink {
                    ScanView(session: session, dependencies: dependencies)
                } label: {
                    Label("Open Camera", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .font(.appBody.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)
                .disabled(!session.patient.isComplete)

                if !session.patient.isComplete {
                    Text("Patient name and medical record number are required.")
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Patient Data")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}

#Preview("Patient Data – empty") {
    NavigationStack {
        PatientDataView(session: ExamSession(), dependencies: AppDependencies())
    }
}

#Preview("Patient Data – filled") {
    let session = ExamSession()
    session.patient.name = "Ahmad Rizki"
    session.patient.medicalRecordNumber = "RM 240724-001"
    session.patient.nationalID = "3204012509900001"
    return NavigationStack {
        PatientDataView(session: session, dependencies: AppDependencies())
    }
}
