import SwiftUI

/// The live preview circle plus its focus badge — moved out of `ScanView` because both are
/// drawn over the same camera feed and the badge only makes sense sitting on top of it.
struct Viewfinder: View {
    let side: CGFloat
    let viewModel: ScanViewModel

    var body: some View {
        VStack(spacing: 0) {
            circle
            focusBadge.padding(.top, 14)
        }
    }

    /// Circular, matching the microscope's own field of view.
    ///
    /// This is safe only because the models are cut to the same circle
    /// (`MultiDetectorService.restrictedToFieldOfView`): detections outside it are discarded, so
    /// everything counted is visible and everything visible is counted. Masking the display
    /// alone would hide roughly 21% of the analysed square while still counting bacilli inside
    /// it — marks the analyst could never check.
    private var circle: some View {
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
}

#Preview("Viewfinder") {
    let session = ExamSession()
    let dependencies = AppDependencies()
    let viewModel = ScanViewModel(
        cameraService: dependencies.cameraService,
        store: dependencies.sessionStore,
        queue: dependencies.queue(for: session)
    )
    return ZStack {
        Color.black.ignoresSafeArea()
        Viewfinder(side: 320, viewModel: viewModel)
    }
}
