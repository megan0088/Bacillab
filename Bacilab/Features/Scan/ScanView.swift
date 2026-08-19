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
                Viewfinder(side: side, viewModel: viewModel)
                Spacer(minLength: 20)
                ShutterBar(
                    viewModel: viewModel,
                    session: session,
                    goToReview: $goToReview,
                    pickedPhoto: $pickedPhoto,
                    isImporting: $isImporting
                )
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
