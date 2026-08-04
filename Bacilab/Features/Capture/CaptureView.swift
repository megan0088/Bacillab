import SwiftUI

struct CaptureView: View {
    @Bindable var draft: SampleDraft
    @State private var viewModel: CaptureViewModel
    let dependencies: AppDependencies
    @State private var navigateToReview = false

    init(draft: SampleDraft, viewModel: CaptureViewModel, dependencies: AppDependencies) {
        self.draft = draft
        _viewModel = State(initialValue: viewModel)
        self.dependencies = dependencies
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                if draft.capturedFieldCount > 0 {
                    fieldCounter
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()
                microscopePreview
                Spacer()

                if draft.capturedFieldCount > 0 {
                    btaResultPanel
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    focusCheckBadge
                    shutterRow
                }
            }
            .animation(.spring(duration: 0.35), value: draft.capturedFieldCount > 0)
        }
        .navigationTitle("Capture Field")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(isPresented: $navigateToReview) {
            AnalysisView(
                draft: draft,
                viewModel: AnalysisViewModel(
                    analysisService: dependencies.analysisService,
                    sampleRepository: dependencies.sampleRepository
                )
            )
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .task { await viewModel.startCamera() }
        .onDisappear { viewModel.stopCamera() }
    }

    // MARK: - Field Counter

    private var fieldCounter: some View {
        Text("\(draft.capturedFieldCount) of \(draft.totalFieldCount) Field")
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.white.opacity(0.08))
    }

    // MARK: - Circular Camera (microscope eyepiece)

    private var microscopePreview: some View {
        ZStack {
            cameraContent

            if draft.capturedFieldCount > 0 {
                // ROI dashed selection box
                Rectangle()
                    .stroke(Color.red.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .frame(width: 180, height: 100)
                    .offset(x: -30, y: -20)

                Rectangle()
                    .stroke(Color.red.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .frame(width: 60, height: 40)
                    .offset(x: 60, y: 40)

                // Confidence badge
                VStack {
                    HStack {
                        Spacer()
                        confidenceBadge
                            .padding(.trailing, 8)
                            .padding(.top, 8)
                    }
                    Spacer()
                }
                .frame(width: 300, height: 300)
            }
        }
        .frame(width: 300, height: 300)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 24, y: 8)
    }

    @ViewBuilder
    private var cameraContent: some View {
        #if targetEnvironment(simulator)
        simulatorTestPattern
        #else
        CameraPreviewView(session: viewModel.session)
            .frame(width: 300, height: 300)
        #endif
    }

    private var simulatorTestPattern: some View {
        ZStack {
            RadialGradient(
                colors: [Color(.systemGray2), Color(.systemGray5), Color(.systemGray6)],
                center: .center,
                startRadius: 0,
                endRadius: 160
            )
            ForEach(simulatedDots, id: \.0) { dot in
                Circle()
                    .fill(.white.opacity(0.25))
                    .frame(width: dot.2, height: dot.2)
                    .offset(x: dot.0, y: dot.1)
            }
            VStack(spacing: 6) {
                Image(systemName: "camera.metering.spot")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.45))
                Text("Simulator Mode")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: 300, height: 300)
    }

    private let simulatedDots: [(CGFloat, CGFloat, CGFloat)] = [
        (-60, -40, 8), (30, -80, 5), (80, 20, 10), (-30, 70, 6),
        (50, 60, 7), (-90, 10, 4), (10, -50, 9), (-50, -90, 5)
    ]

    // MARK: - Confidence Badge

    private var confidenceBadge: some View {
        let pct = draft.aiConfidence > 0
            ? Int(draft.aiConfidence * 100)
            : Int.random(in: 85...95)
        return Text("\(pct)% AI Confidence Level")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.orange.opacity(0.85), in: Capsule())
            .foregroundStyle(.white)
    }

    // MARK: - Focus Check Badge (initial state)

    private var focusCheckBadge: some View {
        Label("Focus Check ✓", systemImage: "checkmark.circle")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.75))
            .padding(.top, 16)
    }

    // MARK: - Shutter Row (initial state)

    private var shutterRow: some View {
        VStack(spacing: 20) {
            Button {
                Task { await viewModel.capture(into: draft) }
            } label: {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.5), lineWidth: 3)
                        .frame(width: 72, height: 72)
                    Circle()
                        .fill(viewModel.isCapturing ? Color(.systemGray4) : .white)
                        .frame(width: 62, height: 62)
                }
            }
            .disabled(viewModel.isCapturing)
            .padding(.bottom, 40)
        }
    }

    // MARK: - BTA Result Panel (after first capture)

    private var btaResultPanel: some View {
        VStack(spacing: 0) {
            // BTA count row
            HStack(alignment: .bottom, spacing: 6) {
                Text("\(draft.manualBTACount)")
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text("BTA")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 8)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(draft.grade.rawValue)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(gradeColor(draft.grade))
                    Text("BTA Terdeteksi")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            // Grade pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BTAGrade.allCases, id: \.self) { grade in
                        CaptureGradePill(grade: grade, isSelected: draft.grade == grade) {
                            draft.grade = grade
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.vertical, 12)

            // Action buttons
            HStack(spacing: 12) {
                // Shutter
                Button {
                    Task { await viewModel.capture(into: draft) }
                } label: {
                    ZStack {
                        Circle().stroke(.white.opacity(0.4), lineWidth: 2).frame(width: 52, height: 52)
                        Circle().fill(.white).frame(width: 44, height: 44)
                    }
                }
                .disabled(viewModel.isCapturing)

                // Continue
                Button {
                    navigateToReview = true
                } label: {
                    Text("Continue")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(.white.opacity(0.05))
    }

    private func gradeColor(_ grade: BTAGrade) -> Color {
        switch grade {
        case .negative: return .green
        case .scanty:   return .orange
        case .plus1, .plus2, .plus3: return .red
        }
    }
}

// MARK: - Grade Pill

private struct CaptureGradePill: View {
    let grade: BTAGrade
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(grade.rawValue)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    isSelected ? Color.accentColor : Color.white.opacity(0.1),
                    in: Capsule()
                )
                .foregroundStyle(.white)
        }
        .animation(.spring(duration: 0.2), value: isSelected)
    }
}

// MARK: - Previews

#Preview("Capture – initial state") {
    let deps = AppDependencies()
    return NavigationStack {
        CaptureView(
            draft: SampleDraft(),
            viewModel: CaptureViewModel(
                cameraService: deps.cameraService,
                analysisService: deps.analysisService,
                sampleRepository: deps.sampleRepository
            ),
            dependencies: deps
        )
    }
}

#Preview("Capture – 12 fields captured") {
    let deps = AppDependencies()
    let draft = SampleDraft.preview
    return NavigationStack {
        CaptureView(
            draft: draft,
            viewModel: CaptureViewModel(
                cameraService: deps.cameraService,
                analysisService: deps.analysisService,
                sampleRepository: deps.sampleRepository
            ),
            dependencies: deps
        )
    }
}
