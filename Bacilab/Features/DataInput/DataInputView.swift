import SwiftUI

struct DataInputView: View {
    @Bindable var draft: SampleDraft
    let dependencies: AppDependencies
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sectionHeader("Patient Information")

                formField(label: "Nama Pasien",        text: $draft.patientName,      placeholder: "Masukkan nama lengkap")
                formField(label: "No. Akses",          text: $draft.accessionNumber,  placeholder: "Contoh: ACC-2025-001")
                dateField(label: "Tanggal Lahir",      date: $draft.dateOfBirth)
                formField(label: "Nama Dokter",        text: $draft.doctorName,       placeholder: "dr. ...")
                formField(label: "No. Telepon",        text: $draft.phone,            placeholder: "08xx-xxxx-xxxx")
                formField(label: "Alamat",             text: $draft.address,          placeholder: "Alamat pasien")
                dateField(label: "Tanggal Pemeriksaan", date: $draft.examinationDate)

                Spacer(minLength: 24)

                NavigationLink {
                    CaptureView(
                        draft: draft,
                        viewModel: CaptureViewModel(
                            cameraService: dependencies.cameraService,
                            analysisService: dependencies.analysisService,
                            sampleRepository: dependencies.sampleRepository
                        ),
                        dependencies: dependencies
                    )
                } label: {
                    Label("Buka Kamera", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)
                .disabled(draft.patientName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Data Pasien")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Batal") { dismiss() }
            }
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(.headline, design: .rounded, weight: .bold))
            .foregroundStyle(Color.accentColor)
    }

    // MARK: - Form Fields

    private func formField(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .padding(14)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
        }
    }

    private func dateField(label: String, date: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                DatePicker("", selection: date, displayedComponents: .date)
                    .labelsHidden()
                Spacer()
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
        }
    }
}

// MARK: - Previews

#Preview("Data Input – empty") {
    let deps = AppDependencies()
    return NavigationStack {
        DataInputView(draft: SampleDraft(), dependencies: deps)
    }
    .environment(deps)
}

#Preview("Data Input – filled") {
    let deps = AppDependencies()
    return NavigationStack {
        DataInputView(draft: SampleDraft.preview, dependencies: deps)
    }
    .environment(deps)
}
