import SwiftUI

/// Data pasien dan sampel, sebelum sesi scan dimulai.
///
/// Dependency diterima sebagai `let` eksplisit, bukan `@Environment`: view ini di-push di
/// dalam `NavigationStack` sebuah sheet, dan `@Environment(AppDependencies.self)` di sana
/// akan crash saat runtime.
struct PatientDataView: View {
    @Bindable var session: ExamSession
    let dependencies: AppDependencies
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sectionHeader("Informasi Pasien")

                formField(label: "No. Rekam Medis", text: $session.patient.medicalRecordNumber,
                          placeholder: "Contoh: RM 240724-001")
                formField(label: "NIK", text: $session.patient.nationalID,
                          placeholder: "16 digit")
                formField(label: "Nama Pasien", text: $session.patient.name,
                          placeholder: "Masukkan nama lengkap")
                dateField(label: "Tanggal Lahir", date: $session.patient.dateOfBirth)
                formField(label: "Alamat", text: $session.patient.address,
                          placeholder: "Alamat pasien")
                formField(label: "No. Telepon", text: $session.patient.phone,
                          placeholder: "08xx-xxxx-xxxx")

                sectionHeader("Informasi Pemeriksaan")

                dateField(label: "Tanggal Pemeriksaan", date: $session.patient.examinationDate)
                dateField(label: "Waktu Pengambilan Sampel", date: $session.patient.sampleCollectedAt,
                          components: [.date, .hourAndMinute])

                Spacer(minLength: 24)

                NavigationLink {
                    ScanView(session: session, dependencies: dependencies)
                } label: {
                    Label("Buka Kamera", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)
                .disabled(!session.patient.isComplete)

                if !session.patient.isComplete {
                    Text("Nama pasien dan nomor rekam medis wajib diisi.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(.headline, design: .rounded, weight: .bold))
            .foregroundStyle(Color.accentColor)
    }

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

    private func dateField(
        label: String,
        date: Binding<Date>,
        components: DatePickerComponents = .date
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                DatePicker("", selection: date, displayedComponents: components)
                    .labelsHidden()
                Spacer()
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

#Preview("Data Pasien – kosong") {
    NavigationStack {
        PatientDataView(session: ExamSession(), dependencies: AppDependencies())
    }
}

#Preview("Data Pasien – terisi") {
    let session = ExamSession()
    session.patient.name = "Ahmad Rizki"
    session.patient.medicalRecordNumber = "RM 240724-001"
    session.patient.nationalID = "3204012509900001"
    return NavigationStack {
        PatientDataView(session: session, dependencies: AppDependencies())
    }
}
