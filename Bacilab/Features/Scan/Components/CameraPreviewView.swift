import SwiftUI
import AVFoundation

// Wraps AVCaptureVideoPreviewLayer for live camera feed display.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// MARK: - Previews

#Preview("Camera Preview – circular (as used in CaptureView)") {
    ZStack {
        Color(.systemGray6).ignoresSafeArea()
        ZStack {
            // On simulator AVCaptureSession produces no feed, so we overlay a label
            CameraPreviewView(session: AVCaptureSession())
                .frame(width: 300, height: 300)

            VStack(spacing: 8) {
                Image(systemName: "camera.metering.spot")
                    .font(.appTitle)
                    .foregroundStyle(.white.opacity(0.5))
                Text("Live on device")
                    .font(.appCaption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .clipShape(Circle())
        .shadow(radius: 12, y: 4)
    }
}
