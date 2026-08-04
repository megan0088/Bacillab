import SwiftUI

// Review screen — manual BTA count entry and grade selection
struct AnalysisView: View {
    @Bindable var draft: SampleDraft
    @State private var viewModel: AnalysisViewModel
    @State private var navigateToResult = false
    @State private var builtSample: Sample?

    init(draft: SampleDraft, viewModel: AnalysisViewModel) {
        self.draft = draft
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
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

            // Floating N → next
            Button {
                let sample = Sample.build(from: draft)
                builtSample = sample
                navigateToResult = true
            } label: {
                Circle()
                    .fill(Color.pink)
                    .frame(width: 56, height: 56)
                    .overlay {
                        Text("N")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                    }
                    .shadow(color: .pink.opacity(0.4), radius: 8, y: 4)
            }
            .padding(24)
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
                Image(systemName: "photo.circle")
                    .font(.system(size: 52))
                    .foregroundStyle(.tertiary)
            }
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

                Text(String(format: "%02d", draft.manualBTACount))
                    .font(.system(size: 52, weight: .bold, design: .monospaced))
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
            Button { } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
        }
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
                            draft.grade = grade
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
