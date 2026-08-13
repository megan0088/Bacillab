import SwiftUI
import PhotosUI

struct CaptureView: View {
    @Bindable var draft: SampleDraft
    @State private var viewModel: CaptureViewModel
    let dependencies: AppDependencies
    @State private var navigateToReview = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isLoadingGalleryImage = false
    @State private var galleryDisplayImage: UIImage?

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
                        detectorComparison
                    }

                    Spacer(minLength: 20)
                    microscopePreview(size: circleSize)
                    Spacer(minLength: 20)

                    if draft.capturedFieldCount > 0 {
                        VStack(spacing: 12) {
                            detectorPicker
                            btaResultPanel
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        VStack(spacing: 20) {
                            detectorPicker
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
                    // Show the photo in the viewfinder before/during analysis, and shut the
                    // camera down: it is not visible, its frames are not analysed, and an
                    // idle capture session still drains and heats the phone.
                    galleryDisplayImage = UIImage(data: data)
                    viewModel.stopCamera()
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
        .onChange(of: viewModel.detectorSelection) { _, selection in
            // Re-point the count of record at the newly chosen model's own total. Without
            // this the running count keeps the fields the previous model read and adds the
            // new one's on top — a number no single detector ever produced, driving the grade.
            draft.adoptCount(from: selection.gradingDetector)
            // Release the frozen frame too: its boxes came from the previous model, and
            // leaving them up would attribute one model's marks to another.
            viewModel.resumeLivePreview()
        }
        .task { await viewModel.startCamera() }
        .onDisappear { viewModel.stopCamera() }
    }

    /// Drops whatever still image is on screen and brings the camera back up.
    ///
    /// The camera is stopped while a gallery photo is displayed — it is not being shown, its
    /// frames are not being analysed, and leaving a capture session running costs battery and
    /// heat on a phone clamped to an eyepiece. Restarting is guarded by `isRunning`, so
    /// calling this when the camera is already live does nothing.
    private func returnToLiveCamera() {
        galleryDisplayImage = nil
        viewModel.resumeLivePreview()
        Task { await viewModel.startCamera() }
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

    // MARK: - Camera (full analysed field)

    private func microscopePreview(size: CGFloat) -> some View {
        ZStack {
            cameraContent(size: size)

            // Each model's own boxes, in its own colour, over the same field. Where the two
            // colours sit apart is exactly where the models disagree — which is the thing
            // worth looking at, and something two totals alone can never show.
            //
            // Flattened to a single list rather than a ForEach per reading nested inside a
            // ForEach: one level, explicit ids, nothing about the drawing that depends on
            // SwiftUI resolving identity across nested loops.
            ForEach(markers, id: \.id) { marker in
                Rectangle()
                    .stroke(
                        Self.tint(for: marker.detector),
                        style: StrokeStyle(
                            lineWidth: 2,
                            // Solid vs dashed as well as colour, so the two stay apart for a
                            // colour-blind reader and in a screenshot.
                            dash: Self.dash(for: marker.detector)
                        )
                    )
                    .frame(
                        width: max(CGFloat(marker.box.w) * size, 8),
                        height: max(CGFloat(marker.box.h) * size, 8)
                    )
                    .rotationEffect(.radians(Double(marker.box.angle)))
                    .offset(
                        x: CGFloat(marker.box.cx - 0.5) * size,
                        y: CGFloat(marker.box.cy - 0.5) * size
                    )
            }

            // Top overlay: gallery source badge (left) + confidence badge (right)
            if draft.capturedFieldCount > 0 || galleryDisplayImage != nil || viewModel.analyzedImage != nil {
                VStack {
                    HStack {
                        // "Dari Galeri" badge with clear button — lets tech switch back to camera
                        if galleryDisplayImage != nil || viewModel.analyzedImage != nil {
                            Button {
                                returnToLiveCamera()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: galleryDisplayImage != nil ? "photo" : "viewfinder")
                                    Text(galleryDisplayImage != nil ? "Dari Galeri" : "Frame dianalisis")
                                    Image(systemName: "xmark")
                                }
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(.black.opacity(0.55), in: Capsule())
                                .foregroundStyle(.white)
                            }
                            .padding(.leading, 10)
                            .padding(.top, 10)
                        }
                        Spacer()
                        if draft.capturedFieldCount > 0 {
                            confidenceBadge
                                .padding(.trailing, 10)
                                .padding(.top, 10)
                        }
                    }
                    Spacer()
                }
                .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        // Tap the frozen frame to go back to live. Freezing is what makes the boxes mean
        // anything, but it also blinds the viewfinder: with a still image on screen the next
        // shutter press is aimed at a field the analyst cannot see. The badge does the same
        // thing, but nobody hunting for the slide will look for a badge first.
        .contentShape(Rectangle())
        .onTapGesture {
            guard viewModel.analyzedImage != nil || galleryDisplayImage != nil else { return }
            returnToLiveCamera()
        }
        // Square, not a circle. The preview layer is `.resizeAspectFill`, so this square is
        // exactly the centred crop `FieldFraming` hands the models — everything shown is
        // analysed and everything analysed is shown. The circular mask hid the corners of
        // that same square (about 21% of it), so bacilli could sit inside the analysed area
        // yet outside anything the analyst could see, with detection boxes drawn over
        // nothing. Aiming the eyepiece is easier against the real edges too.
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14).stroke(
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
        // The frozen frame wins over the live feed: boxes are normalised against the pixels
        // the models were given, so they only mean anything drawn on those same pixels.
        if let image = galleryDisplayImage ?? viewModel.analyzedImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
        } else {
            #if targetEnvironment(simulator)
            simulatorTestPattern(size: size)
            #else
            CameraPreviewView(session: viewModel.session)
                .frame(width: size, height: size)
            #endif
        }
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

    /// One box to draw, tagged with the model that found it.
    ///
    /// Flattening both models' boxes into one list with explicit, unique ids keeps the
    /// overlay a single `ForEach`. The previous shape — a `ForEach` over readings wrapping a
    /// `ForEach` over that reading's boxes, returned from a helper — relied on SwiftUI
    /// resolving identity across two nested loops whose inner ids (`0, 1, 2 …`) repeated for
    /// every model.
    private struct BoxMarker {
        let id: String
        let detector: DetectorKind
        let box: DetectedBox
    }

    /// Every model's boxes for the last analysed field, as one flat list.
    ///
    /// Capped per model so a pathological field cannot put thousands of shapes on screen;
    /// the cap is display-only and never touches the counts.
    private var markers: [BoxMarker] {
        viewModel.latestReadings.flatMap { reading in
            reading.boxes.prefix(80).enumerated().map { index, box in
                BoxMarker(
                    id: "\(reading.detector.rawValue)-\(index)",
                    detector: reading.detector,
                    box: box
                )
            }
        }
    }

    // MARK: - Detector selection

    /// One colour per model, used by both the overlay boxes and the readout below, so the
    /// analyst never has to guess which box belongs to which number.
    /// A distinct dash pattern per model, so the three stay apart for a colour-blind reader
    /// and in a black-and-white screenshot — colour alone cannot carry three categories.
    static func dash(for detector: DetectorKind, scale: CGFloat = 1) -> [CGFloat] {
        switch detector {
        case .resnet: return []
        case .yolo:   return [4 * scale, 3 * scale]
        case .yolo11: return [1.5 * scale, 2.5 * scale]
        }
    }

    static func tint(for detector: DetectorKind) -> Color {
        switch detector {
        case .resnet: return .red
        case .yolo:   return .cyan
        case .yolo11: return .yellow
        }
    }

    /// Picks which model reads the next capture or imported photo.
    ///
    /// Sits above the shutter because it has to be chosen *before* the photo is taken —
    /// the choice cannot be applied retroactively to a field already captured.
    private var detectorPicker: some View {
        VStack(spacing: 4) {
            Picker("Model", selection: $viewModel.detectorSelection) {
                ForEach(DetectorSelection.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)

            Text(viewModel.detectorSelection == .all
                 ? "Semua model membaca lapang yang sama · grade dari \(DetectorKind.resnet.rawValue)"
                 : "Grade dari \(viewModel.detectorSelection.gradingDetector.rawValue)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Detector comparison

    /// Side-by-side running totals for the two models over the same fields.
    ///
    /// ResNet is labelled as the one driving the grade and YOLO as comparison only, because
    /// two numbers next to each other invite the reading that the truth is somewhere between
    /// them. It is not: the reported count is ResNet's, and YOLO is here to be judged, not
    /// averaged in.
    private var detectorComparison: some View {
        let selection = viewModel.detectorSelection
        let grading = selection.gradingDetector

        return HStack(spacing: 0) {
            detectorColumn(
                detector: grading,
                total: draft.count(for: grading),
                fields: draft.fields(for: grading),
                last: viewModel.latestReadings.first { $0.detector == grading },
                caption: "dipakai untuk grade"
            )

            // Only shown for models that actually read the same field. With a single model
            // there is nothing to compare, and an empty column would read as a disagreement
            // rather than as a comparison that was never asked for.
            ForEach(selection.comparisonDetectors, id: \.self) { comparison in
                Divider().frame(height: 34)

                detectorColumn(
                    detector: comparison,
                    total: draft.count(for: comparison),
                    fields: draft.fields(for: comparison),
                    last: viewModel.latestReadings.first { $0.detector == comparison },
                    caption: "pembanding"
                )
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }

    private func detectorColumn(
        detector: DetectorKind,
        total: Int,
        fields: Int,
        last: DetectorReading?,
        caption: String
    ) -> some View {
        VStack(spacing: 2) {
            // Same colour and dash pattern as this model's boxes in the viewfinder above.
            HStack(spacing: 4) {
                Capsule()
                    .stroke(Self.tint(for: detector),
                            style: StrokeStyle(lineWidth: 1.5,
                                               dash: Self.dash(for: detector, scale: 0.7)))
                    .frame(width: 14, height: 8)
                Text(detector.rawValue)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Self.tint(for: detector))
            }

            if let last, let failure = last.failure {
                // Never let a failed read show as 0 — that reads as "saw nothing".
                Text("gagal")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.orange)
                    .help(failure)
            } else {
                Text("\(total)")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
            }

            Text(fields > 0 ? "\(fields) lapang · \(caption)" : caption)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            #if DEBUG
            // Debug-only readout for the model comparison: how many boxes this model handed
            // the overlay for the last field, and how long it took. A count with 0 boxes
            // means the models are fine and the drawing is not — on screen the two are
            // indistinguishable. Compiled out of release builds, so the clinic never sees it.
            if let last {
                Text("\(last.boxes.count) kotak · \(String(format: "%.1f", last.elapsed))s")
                    .font(.system(size: 9))
                    .foregroundStyle(Self.tint(for: detector).opacity(0.8))
            }
            #endif
        }
        .frame(maxWidth: .infinity)
    }

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
                // Bring the camera back before scanning: with a still image on screen the
                // session is stopped, and every frame would throw `sessionNotRunning`.
                if viewModel.analyzedImage != nil || galleryDisplayImage != nil {
                    returnToLiveCamera()
                }
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
                        galleryDisplayImage = nil
                        Task {
                            if viewModel.analyzedImage != nil || galleryDisplayImage != nil {
                                returnToLiveCamera()
                            }
                            await viewModel.capture(into: draft)
                        }
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
                    galleryDisplayImage = nil
                    Task {
                        if viewModel.analyzedImage != nil || galleryDisplayImage != nil {
                            returnToLiveCamera()
                        }
                        await viewModel.capture(into: draft)
                    }
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
