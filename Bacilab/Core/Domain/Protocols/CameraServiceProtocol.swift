import AVFoundation

protocol CameraServiceProtocol: AnyObject {
    var isRunning: Bool { get }
    var session: AVCaptureSession { get }
    func startSession() async throws
    func stopSession()
    func captureImage() async throws -> Data
}
