import SwiftUI

// Review screen — manual BTA count entry and grade selection
struct AnalysisView: View {
    @Bindable var draft: SampleDraft
    @State private var viewModel: AnalysisViewModel
    @State private var navigateToResult = false
    @State private var builtSample: Sample?
    @State private var showGradingInfo = false

    init(draft: SampleDraft, viewModel: AnalysisViewModel) {
        self.draft = draft
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 28) {
                    circularImagePreview
                    btaCountRow
                    descriptionRow
                    gradeSectionView
                    Spacer(minLength: 80)
                }
                .padding(24)
            }

            // Says where it goes, rather than leaving the analyst to decode a letter
            Button {
                let sample = Sample.build(from: draft)
                builtSample = sample
                navigateToResult = true
            } label: {
                Label("Lihat Interpretasi", systemImage: "arrow.right.circle.fill")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToResult) {
            if let sample = builtSample {
                ResultView(
                    viewModel: ResultViewModel(
                        sample: sample,
                        sampleRepository: viewModel.sampleRepository
                    )
                )
            }
        }
    }

    // MARK: - Circular Image

    private var circularImagePreview: some View {
        Circle()
            .fill(Color(.systemGray5))
            .frame(width: 240, height: 240)
            .overlay {
                // Show the field that was actually analysed — reviewing a count
                // without seeing its image is not a review.
                if let data = draft.imageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo.circle")
                        .font(.system(size: 52))
                        .foregroundStyle(.tertiary)
                }
            }
            .clipShape(Circle())
            .overlay(Circle().stroke(Color(.systemGray4), lineWidth: 1))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }

    // MARK: - BTA Count

    private var btaCountRow: some View {
        HStack(spacing: 0) {
            HStack(spacing: 16) {
                Button {
                    if draft.manualBTACount > 0 { draft.manualBTACount -= 1 }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color(.systemGray3))
                }

                // A full 100-field read reaches four digits, which wraps at this size
                Text(String(format: "%02d", draft.manualBTACount))
                    .font(.system(size: 52, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(minWidth: 80)
                    .contentTransition(.numericText())

                Button {
                    draft.manualBTACount += 1
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
            }

            Spacer()

            Text("BTA")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Description

    private var descriptionRow: some View {
        HStack {
            Text("Masukkan jumlah BTA yang ditemukan pada seluruh lapang pandang")
                .font(.appCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button {
                showGradingInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
            .sheet(isPresented: $showGradingInfo) { gradingInfoSheet }
        }
    }

    private var gradingInfoSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Sistem grading WHO/IUATLD didasarkan pada jumlah BTA yang ditemukan per 100 lapang pandang.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 0) {
                        gradingRow(grade: "Negatif", criteria: "0 BTA dalam 100 lapang", color: .green)
                        Divider().padding(.leading, 16)
                        gradingRow(grade: "Scanty",  criteria: "1–9 BTA dalam 100 lapang", color: .orange)
                        Divider().padding(.leading, 16)
                        gradingRow(grade: "1+",      criteria: "10–99 BTA dalam 100 lapang", color: .red)
                        Divider().padding(.leading, 16)
                        gradingRow(grade: "2+",      criteria: "1–10 BTA per lapang (≥50 lapang)", color: .red)
                        Divider().padding(.leading, 16)
                        gradingRow(grade: "3+",      criteria: ">10 BTA per lapang (≥20 lapang)", color: .red)
                    }
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))

                    Text("Grading bersifat SEMENTARA sampai jumlah lapang minimum terpenuhi.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Panduan Grading BTA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tutup") { showGradingInfo = false }
                }
            }
        }
    }

    private func gradingRow(grade: String, criteria: String, color: Color) -> some View {
        HStack {
            Text(grade)
                .font(.system(.body, design: .rounded, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 64, alignment: .leading)
            Text(criteria)
                .font(.callout)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Grade Pills

    private var gradeSectionView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tentukan Grading")
                .font(.appCaption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BTAGrade.allCases, id: \.self) { grade in
                        GradePill(grade: grade, isSelected: draft.grade == grade) {
                            draft.selectGrade(grade)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Grade Pill

private struct GradePill: View {
    let grade: BTAGrade
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(grade.rawValue)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(isSelected ? Color.pink : Color(.systemGray5), in: Capsule())
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .animation(.spring(duration: 0.2), value: isSelected)
    }
}

// MARK: - Previews

#Preview("Review – fresh") {
    let deps = AppDependencies()
    let draft = SampleDraft()
    draft.patientName = "Ahmad Rizki"
    draft.capturedFieldCount = 13
    return NavigationStack {
        AnalysisView(
            draft: draft,
            viewModel: AnalysisViewModel(
                analysisService: deps.analysisService,
                sampleRepository: deps.sampleRepository
            )
        )
    }
    .environment(deps)
}

#Preview("Review – with BTA count") {
    let deps = AppDependencies()
    return NavigationStack {
        AnalysisView(
            draft: SampleDraft.preview,
            viewModel: AnalysisViewModel(
                analysisService: deps.analysisService,
                sampleRepository: deps.sampleRepository
            )
        )
    }
    .environment(deps)
}
