import PhotosUI
import SwiftUI

/// The scan session. Produces fields, and knows nothing about BTA.
///
/// This screen is deliberately bare: the technician is at the eyepiece, not watching the phone.
/// Counts, grade, model comparison and confidence all live in Review, where they are sitting
/// down and deciding.
struct ScanView: View {
    @Bindable var session: ExamSession
    @State private var viewModel: ScanViewModel
    let dependencies: AppDependencies
    @State private var goToReview = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var isImporting = false

    init(session: ExamSession, dependencies: AppDependencies) {
        self.session = session
        self.dependencies = dependencies
        _viewModel = State(initialValue: ScanViewModel(
            cameraService: dependencies.cameraService,
            store: dependencies.sessionStore,
            queue: dependencies.makeAnalysisQueue()
        ))
    }

    var body: some View {
        GeometryReader { geo in
            let side: CGFloat = min(geo.size.width - 32, 360)

            VStack(spacing: 0) {
                fieldCounter
                Spacer(minLength: 20)
                viewfinder(side: side)
                focusBadge.padding(.top, 14)
                Spacer(minLength: 20)
                controls
                    .padding(.bottom, max(geo.safeAreaInsets.bottom + 16, 32))
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle("Scan Session")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $goToReview) {
            ReviewView(session: session, queue: viewModel.queue, dependencies: dependencies)
        }
        .alert("Something went wrong", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Camera access needed", isPresented: $viewModel.permissionDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The app cannot reach the camera to scan the slide. "
                 + "Enable camera access in Settings, then open this screen again.")
        }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            isImporting = true
            Task {
                defer {
                    isImporting = false
                    pickedPhoto = nil
                }
                // Importing while the scan loop is running would interleave two sources into
                // one field sequence, so stop it first and let the analyst restart deliberately.
                viewModel.stopScan()
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    viewModel.errorMessage = "That photo could not be loaded."
                    return
                }
                await viewModel.importField(from: data, into: session)
            }
        }
        .task { await viewModel.startCamera() }
        .onDisappear { viewModel.stopCamera() }
    }

    // MARK: - Sections

    /// The end of the batch currently being filled — 20, then 40, and so on.
    ///
    /// Scanning is not capped at one batch: reaching 2+ takes 50 fields and Negative takes 100,
    /// so the counter has to keep moving past 20 rather than sitting at a ceiling.
    private var batchCeiling: Int {
        (session.fields.count / ExamSession.batchTarget + 1) * ExamSession.batchTarget
    }

    private var fieldCounter: some View {
        VStack(spacing: 4) {
            Text("\(session.fields.count) of \(batchCeiling) fields")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .contentTransition(.numericText())

            ProgressView(
                value: Double(session.fields.count % ExamSession.batchTarget),
                total: Double(ExamSession.batchTarget)
            )
            .tint(Color.accentColor)
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
    }

    /// Square, not a circle.
    ///
    /// The preview layer is `resizeAspectFill`, so this square is exactly the crop the models
    /// receive. The dashed circle inside it is only a guide for aiming the eyepiece — it clips
    /// nothing. A circular *mask* would hide this square's corners, roughly 21% of its area,
    /// which the models still read and still count.
    private func viewfinder(side: CGFloat) -> some View {
        ZStack {
            #if targetEnvironment(simulator)
            RadialGradient(
                colors: [Color(.systemGray2), Color(.systemGray5), Color(.systemGray6)],
                center: .center, startRadius: 0, endRadius: side * 0.53
            )
            Text("Simulator")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
            #else
            CameraPreviewView(session: viewModel.session)
            #endif

            Circle()
                .stroke(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                .padding(2)
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(viewModel.isScanning ? Color.accentColor : Color(.systemGray3),
                        lineWidth: viewModel.isScanning ? 3 : 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 20, y: 6)
    }

    private var focusBadge: some View {
        Group {
            if viewModel.isBlurry {
                Label("Focus not sharp", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                Label("Focus sharp", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption.weight(.semibold))
        .animation(.easeInOut(duration: 0.2), value: viewModel.isBlurry)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            Button {
                viewModel.toggleScan(session: session)
            } label: {
                ZStack {
                    Circle()
                        .stroke(viewModel.isScanning ? Color.accentColor : Color(.systemGray3),
                                lineWidth: 3)
                        .frame(width: 80, height: 80)
                    Circle()
                        .fill(viewModel.isScanning ? Color.accentColor : Color(.systemGray6))
                        .frame(width: 68, height: 68)
                    Image(systemName: viewModel.isScanning ? "stop.fill" : "viewfinder.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(viewModel.isScanning ? .white : Color.accentColor)
                }
            }

            Text(viewModel.isScanning ? "Tap to stop" : "Start Scan")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            // Importing a photo is the only way to exercise detection without a microscope
            // clamped to the phone, so it sits beside the shutter rather than being buried.
            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                Label(
                    isImporting ? "Importing…" : "Import Photo",
                    systemImage: isImporting ? "hourglass" : "photo.on.rectangle.angled"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
            .disabled(isImporting)

            if !session.fields.isEmpty {
                Button {
                    viewModel.stopScan()
                    session.status = .reviewing
                    goToReview = true
                } label: {
                    Text("Done · Go to Review")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 32)
                .padding(.top, 6)
            }
        }
    }
}

#Preview("Scan – no fields yet") {
    NavigationStack {
        ScanView(session: ExamSession(), dependencies: AppDependencies())
    }
}

#Preview("Scan – 8 fields") {
    let session = ExamSession()
    for _ in 0..<8 { session.appendField(imageFileName: "f.jpg") }
    return NavigationStack {
        ScanView(session: session, dependencies: AppDependencies())
    }
}
