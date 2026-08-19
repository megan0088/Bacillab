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
            queue: dependencies.queue(for: session)
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
        .background(Color.black)
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle("Capture Field")
        .navigationBarTitleDisplayMode(.inline)
        // The capture screens are dark by design: the technician is looking into an eyepiece in
        // a dim room, and a white screen beside it wrecks their dark adaptation.
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
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
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                Text("\(session.fields.count) of \(batchCeiling)")
                    .font(.appBody.weight(.bold))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text("Field to go")
                    .font(.appCaption)
                    .foregroundStyle(.white.opacity(0.55))
            }

            ProgressView(
                value: Double(session.fields.count % ExamSession.batchTarget),
                total: Double(ExamSession.batchTarget)
            )
            .tint(Color.accentColor)
            .padding(.horizontal, 60)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    /// Circular, matching the microscope's own field of view.
    ///
    /// This is safe only because the models are cut to the same circle
    /// (`MultiDetectorService.restrictedToFieldOfView`): detections outside it are discarded, so
    /// everything counted is visible and everything visible is counted. Masking the display
    /// alone would hide roughly 21% of the analysed square while still counting bacilli inside
    /// it — marks the analyst could never check.
    private func viewfinder(side: CGFloat) -> some View {
        ZStack {
            #if targetEnvironment(simulator)
            RadialGradient(
                colors: [Color(.systemGray2), Color(.systemGray5), Color(.systemGray6)],
                center: .center, startRadius: 0, endRadius: side * 0.53
            )
            Text("Simulator")
                .font(.appCaption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
            #else
            CameraPreviewView(session: viewModel.session)
            #endif

        }
        .frame(width: side, height: side)
        .clipShape(Circle())
        .overlay(
            Circle().stroke(viewModel.isScanning ? Color.accentColor : .white.opacity(0.25),
                            lineWidth: viewModel.isScanning ? 3 : 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 20, y: 6)
    }

    private var focusBadge: some View {
        Group {
            if viewModel.isBlurry {
                Label("Camera out of focus", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                Label("Focus sharp", systemImage: "checkmark.circle")
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .font(.appCaption.weight(.semibold))
        .animation(.easeInOut(duration: 0.2), value: viewModel.isBlurry)
    }

    private var controls: some View {
        VStack(spacing: 16) {
            // A white shutter on black, the way every camera app draws it — the one control the
            // technician has to find without looking away from the eyepiece.
            Button {
                viewModel.toggleScan(session: session)
            } label: {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(viewModel.isScanning ? 1 : 0.45), lineWidth: 3)
                        .frame(width: 78, height: 78)
                    Circle()
                        .fill(viewModel.isScanning ? Color.accentColor : .white)
                        .frame(width: 64, height: 64)
                    if viewModel.isScanning {
                        Image(systemName: "stop.fill")
                            .font(.appHeading)
                            .foregroundStyle(.white)
                    }
                }
            }

            Text(viewModel.isScanning ? "Tap to stop" : "Start Scan")
                .font(.appCaption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))

            HStack(spacing: 10) {
                // Importing is the only way to exercise detection without a microscope clamped
                // to the phone, so it stays beside the shutter rather than being buried.
                PhotosPicker(selection: $pickedPhoto, matching: .images) {
                    Label(
                        isImporting ? "Importing…" : "Import Photo",
                        systemImage: isImporting ? "hourglass" : "photo.on.rectangle.angled"
                    )
                    .font(.appCaption.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(.white.opacity(0.12), in: Capsule())
                }
                .disabled(isImporting)

                if !session.fields.isEmpty {
                    Button {
                        viewModel.stopScan()
                        session.status = .reviewing
                        goToReview = true
                    } label: {
                        Label("Review", systemImage: "arrow.right")
                            .font(.appCaption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(Color.accentColor, in: Capsule())
                    }
                }
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
