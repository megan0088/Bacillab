import AVFoundation

final class CameraService: NSObject, CameraServiceProtocol {
    private let captureSession = AVCaptureSession()
    private(set) var isRunning = false

    var session: AVCaptureSession { captureSession }

    func startSession() async throws {
        guard !isRunning else { return }
        #if targetEnvironment(simulator)
        isRunning = true
        return
        #else
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status != .authorized {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else { throw CameraError.permissionDenied }
        }
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device)
        else { throw CameraError.deviceUnavailable }
        if captureSession.canAddInput(input) { captureSession.addInput(input) }
        captureSession.commitConfiguration()
        captureSession.startRunning()
        isRunning = true
        #endif
    }

    func stopSession() {
        #if !targetEnvironment(simulator)
        captureSession.stopRunning()
        #endif
        isRunning = false
    }

    func captureImage() async throws -> Data {
        #if targetEnvironment(simulator)
        return Data()           // placeholder — non-empty JPEG would come from AVCapturePhotoOutput
        #else
        throw CameraError.notImplemented
        #endif
    }
}

enum CameraError: Error {
    case permissionDenied
    case deviceUnavailable
    case notImplemented
}
