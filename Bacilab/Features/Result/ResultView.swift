import SwiftUI

// Interpretation screen — final result summary
struct ResultView: View {
    @State private var viewModel: ResultViewModel

    init(viewModel: ResultViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    private var grade: BTAGrade {
        viewModel.sample.analysisResult?.grade ?? .negative
    }

    private var gradeColor: Color {
        switch grade {
        case .negative:           return .green
        case .scanty:             return .orange
        case .plus1, .plus2, .plus3: return .red
        }
    }

    private var gradeLabel: String {
        switch grade {
        case .negative: return "Negatif"
        case .scanty:   return "Scanty (Borderline)"
        case .plus1:    return "Positif (1+)"
        case .plus2:    return "Positif (2+)"
        case .plus3:    return "Positif (3+)"
        }
    }

    private var gradeDescription: String {
        switch grade {
        case .negative:
            return "Tidak ditemukan BTA dalam 100 lapang pandang."
        case .scanty:
            return "Ditemukan 1–9 BTA dalam 100 lapang pandang. Perlu pemeriksaan ulang."
        case .plus1:
            return "Ditemukan 10–99 BTA dalam 100 lapang pandang."
        case .plus2:
            return "Ditemukan 1–10 BTA per lapang pandang dalam setidaknya 50 lapang."
        case .plus3:
            return "Ditemukan lebih dari 10 BTA per lapang pandang dalam setidaknya 20 lapang."
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                patientInfoSection
                gradeCard
                statsSection
                notesSection
                saveButton
                    .padding(.bottom, 32)
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Interpretation")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Patient Info

    private var patientInfoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Patient Information")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 12)

            VStack(spacing: 0) {
                infoRow(label: "Lab",               value: "Klinik Bunda")
                Divider().padding(.leading, 100)
                infoRow(label: "Nama",              value: viewModel.sample.patientName)
                Divider().padding(.leading, 100)
                infoRow(label: "No. Akses",         value: viewModel.sample.accessionNumber.isEmpty ? "-" : viewModel.sample.accessionNumber)
                Divider().padding(.leading, 100)
                infoRow(label: "Tanggal Lahir",     value: viewModel.sample.dateOfBirth.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "id_ID"))))
                Divider().padding(.leading, 100)
                infoRow(label: "Tgl. Pemeriksaan",  value: viewModel.sample.examinationDate.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "id_ID"))))
            }
        }
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Grade Card

    private var gradeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Result")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text("In Suggested Grade")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Colored grade banner
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: grade == .negative ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                        .font(.title2)
                    Text(gradeLabel)
                        .font(.system(.title2, design: .rounded, weight: .black))
                }
                Text(gradeDescription)
                    .font(.caption)
                    .opacity(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(gradeColor, in: RoundedRectangle(cornerRadius: 14))

            if !isGradeReportable {
                Label(
                    "Baru \(viewModel.sample.capturedFieldCount) lapang pandang dibaca. "
                    + "Grade \(grade.rawValue) memerlukan \(grade.minimumFields) lapang "
                    + "(WHO/IUATLD), jadi hasil ini belum final.",
                    systemImage: "exclamationmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    /// Enough fields read for this grade to stand as a report, per WHO/IUATLD.
    private var isGradeReportable: Bool {
        viewModel.sample.capturedFieldCount >= grade.minimumFields
    }

    // MARK: - Stats

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            let result = viewModel.sample.analysisResult
            let confPct = result.map { Int($0.confidence * 100) } ?? 0

            HStack(spacing: 0) {
                statCell(
                    icon: "scope",
                    label: "Total Lapang",
                    value: "\(viewModel.sample.capturedFieldCount)/\(viewModel.sample.totalFieldCount)"
                )
                Divider().frame(height: 56)
                statCell(
                    icon: "microbe.fill",
                    label: "Total BTA",
                    value: "\(result?.btaCount ?? 0)"
                )
                Divider().frame(height: 56)
                statCell(
                    icon: "cpu",
                    label: "AI Confidence",
                    value: "\(confPct)%"
                )
            }
        }
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func statCell(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .bold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Lab Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Catatan Laboratorium")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            TextEditor(text: Binding(
                get: { viewModel.notes },
                set: { viewModel.notes = $0 }
            ))
            .frame(minHeight: 90)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                if viewModel.notes.isEmpty {
                    Text("Tambahkan catatan laboratorium...")
                        .font(.system(.body))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 18)
                        .padding(.leading, 14)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button {
            Task { await viewModel.save() }
        } label: {
            HStack {
                if viewModel.isSaving {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: viewModel.isSaved ? "checkmark.circle.fill" : "square.and.arrow.down.fill")
                }
                Text(viewModel.isSaved ? "Tersimpan" : "Simpan Hasil")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(viewModel.isSaved ? .green : Color.accentColor)
        .disabled(viewModel.isSaving || viewModel.isSaved)
    }
}

// MARK: - Previews

#Preview("Interpretation – positif 2+") {
    NavigationStack {
        ResultView(
            viewModel: ResultViewModel(
                sample: Sample.previews[0],
                sampleRepository: AppDependencies().sampleRepository
            )
        )
    }
}

#Preview("Interpretation – negatif") {
    NavigationStack {
        ResultView(
            viewModel: ResultViewModel(
                sample: Sample.previews[1],
                sampleRepository: AppDependencies().sampleRepository
            )
        )
    }
}

#Preview("Interpretation – pending") {
    NavigationStack {
        ResultView(
            viewModel: ResultViewModel(
                sample: Sample.previews[2],
                sampleRepository: AppDependencies().sampleRepository
            )
        )
    }
}
