import SwiftUI
import PhotosUI

struct CaptureView: View {
    @Bindable var draft: SampleDraft
    @State private var viewModel: CaptureViewModel
    let dependencies: AppDependencies
    @State private var navigateToReview = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isLoadingGalleryImage = false

    init(draft: SampleDraft, viewModel: CaptureViewModel, dependencies: AppDependencies) {
        self.draft = draft
        _viewModel = State(initialValue: viewModel)
        self.dependencies = dependencies
    }

    var body: some View {
        GeometryReader { geo in
            let circleSize: CGFloat = min(geo.size.width - 32, 360)

            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    if draft.capturedFieldCount > 0 {
                        fieldCounter
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    Spacer(minLength: 20)
                    microscopePreview(size: circleSize)
                    Spacer(minLength: 20)

                    if draft.capturedFieldCount > 0 {
                        btaResultPanel
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        VStack(spacing: 24) {
                            focusCheckBadge
                            shutterButton
                        }
                        .padding(.bottom, max(geo.safeAreaInsets.bottom + 16, 40))
                    }
                }
                .animation(.spring(duration: 0.35), value: draft.capturedFieldCount > 0)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle("Capture Field")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToReview) {
            AnalysisView(
                draft: draft,
                viewModel: AnalysisViewModel(
                    analysisService: dependencies.analysisService,
                    sampleRepository: dependencies.sampleRepository
                )
            )
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            isLoadingGalleryImage = true
            Task {
                defer {
                    isLoadingGalleryImage = false
                    selectedPhotoItem = nil
                }
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    await viewModel.analyzeGalleryImage(data: data, into: draft)
                } else {
                    viewModel.errorMessage = "Gagal memuat foto dari galeri."
                }
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Izin Kamera Diperlukan", isPresented: $viewModel.permissionDenied) {
            Button("Buka Pengaturan") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Batal", role: .cancel) {}
        } message: {
            Text("Aplikasi tidak dapat mengakses kamera untuk memindai preparat. "
                 + "Aktifkan izin kamera di Pengaturan, lalu buka kembali layar ini.")
        }
        .task { await viewModel.startCamera() }
        .onDisappear { viewModel.stopCamera() }
    }

    // MARK: - Field Counter

    private var fieldCounter: some View {
        Text("\(draft.capturedFieldCount) of \(draft.totalFieldCount) Field")
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.systemGray6))
    }

    // MARK: - Circular Camera (microscope eyepiece)

    private func microscopePreview(size: CGFloat) -> some View {
        ZStack {
            cameraContent(size: size)

            // Dynamic bounding boxes from AI detections
            if !viewModel.latestDetections.isEmpty {
                ForEach(Array(viewModel.latestDetections.prefix(40).enumerated()), id: \.offset) { _, box in
                    let dx = CGFloat(box.cx - 0.5) * size
                    let dy = CGFloat(box.cy - 0.5) * size
                    let bw = max(CGFloat(box.w) * size, 6)
                    let bh = max(CGFloat(box.h) * size, 6)

                    Rectangle()
                        .stroke(
                            viewModel.detectedFlash ? Color.green.opacity(0.9) : Color.red.opacity(0.85),
                            style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                        )
                        .frame(width: bw, height: bh)
                        .rotationEffect(.radians(Double(box.angle)))
                        .offset(x: dx, y: dy)
                        .animation(.easeInOut(duration: 0.2), value: viewModel.detectedFlash)
                }
            }

            // Confidence badge (visible once we have captures)
            if draft.capturedFieldCount > 0 {
                VStack {
                    HStack {
                        Spacer()
                        confidenceBadge
                            .padding(.trailing, 10)
                            .padding(.top, 10)
                    }
                    Spacer()
                }
                .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle().stroke(
                viewModel.detectedFlash ? Color.green : Color(.systemGray3),
                lineWidth: viewModel.detectedFlash ? 3 : 1
            )
            .animation(.easeInOut(duration: 0.2), value: viewModel.detectedFlash)
        )
        .shadow(
            color: viewModel.detectedFlash ? .green.opacity(0.4) : .black.opacity(0.08),
            radius: 20, y: 6
        )
    }

    @ViewBuilder
    private func cameraContent(size: CGFloat) -> some View {
        #if targetEnvironment(simulator)
        simulatorTestPattern(size: size)
        #else
        CameraPreviewView(session: viewModel.session)
            .frame(width: size, height: size)
        #endif
    }

    private func simulatorTestPattern(size: CGFloat) -> some View {
        ZStack {
            RadialGradient(
                colors: [Color(.systemGray2), Color(.systemGray5), Color(.systemGray6)],
                center: .center,
                startRadius: 0,
                endRadius: size * 0.53
            )
            ForEach(simulatedDots, id: \.0) { dot in
                let scale = size / 300
                Circle()
                    .fill(.white.opacity(0.25))
                    .frame(width: dot.2, height: dot.2)
                    .offset(x: dot.0 * scale, y: dot.1 * scale)
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
        .frame(width: size, height: size)
    }

    private let simulatedDots: [(CGFloat, CGFloat, CGFloat)] = [
        (-60, -40, 8), (30, -80, 5), (80, 20, 10), (-30, 70, 6),
        (50, 60, 7), (-90, 10, 4), (10, -50, 9), (-50, -90, 5)
    ]

    // MARK: - Confidence Badge

    private var confidenceBadge: some View {
        // Never invent a number here: this reads as a diagnostic figure to the
        // technician. Until the detector reports a confidence there is none to show.
        let pct = Int((draft.aiConfidence * 100).rounded())
        return Text("\(pct)% AI Confidence Level")
            .opacity(draft.aiConfidence > 0 ? 1 : 0)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.orange.opacity(0.85), in: Capsule())
            .foregroundStyle(.white)
    }

    // MARK: - Focus Check Badge (initial state)

    private var focusCheckBadge: some View {
        Group {
            if viewModel.isAutoScanning {
                Label("Memindai bakteri…", systemImage: "dot.radiowaves.left.and.right")
                    .foregroundStyle(viewModel.detectedFlash ? .green : .secondary)
            } else {
                Label("Focus Check ✓", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption.weight(.semibold))
        .animation(.easeInOut(duration: 0.2), value: viewModel.detectedFlash)
    }

    // MARK: - Shutter Button (initial state)

    private var shutterButton: some View {
        VStack(spacing: 14) {
            // Auto-scan toggle — primary action
            Button {
                viewModel.toggleAutoScan(into: draft)
            } label: {
                ZStack {
                    if viewModel.isAutoScanning {
                        Circle()
                            .stroke(
                                viewModel.detectedFlash ? Color.green : Color.accentColor,
                                lineWidth: 3
                            )
                            .frame(width: 80, height: 80)
                            .scaleEffect(viewModel.detectedFlash ? 1.15 : 1.0)
                            .animation(.spring(duration: 0.3), value: viewModel.detectedFlash)
                    } else {
                        Circle()
                            .stroke(Color(.systemGray3), lineWidth: 3)
                            .frame(width: 80, height: 80)
                    }

                    Circle()
                        .fill(viewModel.isAutoScanning ? Color.accentColor : Color(.systemGray6))
                        .frame(width: 68, height: 68)

                    Image(systemName: viewModel.isAutoScanning ? "stop.fill" : "viewfinder.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(viewModel.isAutoScanning ? .white : Color.accentColor)
                }
            }

            Text(viewModel.isAutoScanning ? "Ketuk untuk berhenti" : "Auto Scan")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            // Manual capture and gallery — secondary fallbacks
            if !viewModel.isAutoScanning {
                HStack(spacing: 10) {
                    Button {
                        Task { await viewModel.capture(into: draft) }
                    } label: {
                        Label("Manual", systemImage: "camera")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray5), in: Capsule())
                    }
                    .disabled(viewModel.isCapturing)

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label(
                            isLoadingGalleryImage ? "Memuat…" : "Galeri",
                            systemImage: isLoadingGalleryImage ? "hourglass" : "photo.on.rectangle"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray5), in: Capsule())
                    }
                    .disabled(viewModel.isCapturing || isLoadingGalleryImage)
                }
            }
        }
    }

    // MARK: - BTA Result Panel (after first capture)

    private var btaResultPanel: some View {
        VStack(spacing: 0) {
            Divider()

            // BTA count row
            HStack(alignment: .bottom, spacing: 6) {
                Text("\(draft.manualBTACount)")
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                Text("BTA")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 5) {
                        if !draft.isGradeConfirmed {
                            Text("SEMENTARA")
                                .font(.system(size: 9, weight: .heavy, design: .rounded))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                        Text(draft.grade.rawValue)
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .foregroundStyle(gradeColor(draft.grade))
                    }
                    // Below the WHO/IUATLD minimum this grade is not reportable yet,
                    // so say what is still missing instead of implying a conclusion.
                    Text(draft.isGradeConfirmed
                         ? "BTA Terdeteksi"
                         : "Perlu \(draft.fieldsRemainingForGrade) lapang lagi")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            // Grade pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BTAGrade.allCases, id: \.self) { grade in
                        CaptureGradePill(grade: grade, isSelected: draft.grade == grade) {
                            draft.selectGrade(grade)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.vertical, 12)

            // Action buttons
            VStack(spacing: 10) {
                Button {
                    Task { await viewModel.capture(into: draft) }
                } label: {
                    Label(
                        viewModel.isCapturing ? "Memproses…" : "Ambil Lapang Berikutnya",
                        systemImage: "camera.fill"
                    )
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
                }
                .disabled(viewModel.isCapturing || isLoadingGalleryImage)
                .opacity(viewModel.isCapturing ? 0.6 : 1)

                HStack(spacing: 10) {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label(
                            isLoadingGalleryImage ? "Memuat…" : "Pilih dari Galeri",
                            systemImage: isLoadingGalleryImage ? "hourglass" : "photo.on.rectangle.angled"
                        )
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(Color.accentColor)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .disabled(viewModel.isCapturing || isLoadingGalleryImage)

                    Button {
                        navigateToReview = true
                    } label: {
                        Text("Selesai")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(.secondary)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
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
                    isSelected ? Color.accentColor : Color(.systemGray5),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? .white : .primary)
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
