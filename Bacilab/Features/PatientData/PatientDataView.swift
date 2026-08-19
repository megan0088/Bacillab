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

                formField("Medical Record Number (MRN)", text: $session.patient.medicalRecordNumber)
                formField("NIK", text: $session.patient.nationalID)
                formField("Patient Name", text: $session.patient.name)
                dateField("Date of Birth", date: $session.patient.dateOfBirth)
                formField("Address", text: $session.patient.address)
                formField("Phone Number", text: $session.patient.phone)

                SectionHeader("Test Information", tinted: true)

                dateField("Examination Date", date: $session.patient.examinationDate)
                dateField("Sample Collection Time", date: $session.patient.sampleCollectedAt,
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

    private func formField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .padding(14)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
    }

    /// A date picker has no placeholder to put a name in, so its name stays a leading label —
    /// which is also how the hi-fi draws these rows.
    private func dateField(
        _ label: String,
        date: Binding<Date>,
        components: DatePickerComponents = .date
    ) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            DatePicker("", selection: date, displayedComponents: components)
                .labelsHidden()
        }
        .padding(14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
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
