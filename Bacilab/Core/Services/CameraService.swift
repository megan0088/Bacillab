import AVFoundation
import UIKit

final class CameraService: NSObject, CameraServiceProtocol {
    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.eganugraha.Bacilab.camera-session")
    private(set) var isRunning = false

    // Held only for the duration of one capture — AVCapturePhotoOutput does not
    // retain its delegate, so letting this go early would drop the callback.
    private var activeCapture: PhotoCaptureDelegate?

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
        // Configuring and starting a session blocks for a noticeable moment; on the
        // main thread that reads as the capture screen freezing as it opens.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [captureSession, photoOutput] in
                captureSession.beginConfiguration()
                captureSession.sessionPreset = .photo
                guard
                    let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                    let input = try? AVCaptureDeviceInput(device: device)
                else {
                    captureSession.commitConfiguration()
                    continuation.resume(throwing: CameraError.deviceUnavailable)
                    return
                }
                if captureSession.canAddInput(input) { captureSession.addInput(input) }
                guard captureSession.canAddOutput(photoOutput) else {
                    captureSession.commitConfiguration()
                    continuation.resume(throwing: CameraError.deviceUnavailable)
                    return
                }
                captureSession.addOutput(photoOutput)
                captureSession.commitConfiguration()
                captureSession.startRunning()
                continuation.resume()
            }
        }
        isRunning = true
        #endif
    }

    func stopSession() {
        #if !targetEnvironment(simulator)
        // stopRunning() blocks too, and this is called from onDisappear
        sessionQueue.async { [captureSession] in captureSession.stopRunning() }
        #endif
        isRunning = false
    }

    func captureImage() async throws -> Data {
        #if targetEnvironment(simulator)
        return Self.syntheticFieldJPEG()
        #else
        guard isRunning else { throw CameraError.sessionNotRunning }
        guard photoOutput.connection(with: .video)?.isActive == true else {
            throw CameraError.deviceUnavailable
        }

        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        return try await withCheckedThrowingContinuation { continuation in
            let delegate = PhotoCaptureDelegate { [weak self] result in
                self?.activeCapture = nil
                continuation.resume(with: result)
            }
            activeCapture = delegate
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
        #endif
    }
}

// MARK: - Photo delegate

// Bridges AVCapturePhotoOutput's delegate callback to the async caller.
private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Result<Data, Error>) -> Void
    private var hasFinished = false

    init(completion: @escaping (Result<Data, Error>) -> Void) {
        self.completion = completion
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        // A continuation may only be resumed once, whatever AVFoundation reports.
        guard !hasFinished else { return }
        hasFinished = true

        if let error {
            completion(.failure(error))
        } else if let data = photo.fileDataRepresentation() {
            completion(.success(data))
        } else {
            completion(.failure(CameraError.captureFailed))
        }
    }
}

// MARK: - Simulator stand-in

#if targetEnvironment(simulator)
extension CameraService {
    /// The simulator has no camera, so synthesise a stained field: pale background,
    /// scattered rod-shaped marks. This exists purely so the capture → detection
    /// pipeline can be exercised without hardware, and is compiled out of device
    /// builds entirely — a real slide never goes through here.
    static func syntheticFieldJPEG() -> Data {
        let side = 1024.0
        // Scale 1, or the renderer would rasterise at the screen's scale factor and
        // hand the detector a 3072px image to downsample for nothing.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let image = renderer.image { context in
            UIColor(red: 232 / 255, green: 214 / 255, blue: 226 / 255, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))

            let cg = context.cgContext
            cg.setStrokeColor(UIColor(red: 150 / 255, green: 30 / 255, blue: 90 / 255, alpha: 1).cgColor)
            cg.setLineCap(.round)

            // Fixed seed keeps the field identical between runs, so the count is stable
            var rng = SeededGenerator(seed: 20_260_804)
            for _ in 0..<60 {
                let x = Double.random(in: 60...(side - 60), using: &rng)
                let y = Double.random(in: 60...(side - 60), using: &rng)
                let angle = Double.random(in: 0...Double.pi, using: &rng)
                let length = Double.random(in: 18...34, using: &rng)
                let width = Double.random(in: 4...7, using: &rng)

                let dx = cos(angle) * length / 2
                let dy = sin(angle) * length / 2
                cg.setLineWidth(width)
                cg.move(to: CGPoint(x: x - dx, y: y - dy))
                cg.addLine(to: CGPoint(x: x + dx, y: y + dy))
                cg.strokePath()
            }
        }
        return image.jpegData(compressionQuality: 0.95) ?? Data()
    }
}

// Deterministic PRNG (SplitMix64) — Swift's default generator is not seedable.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
#endif

enum CameraError: LocalizedError {
    case permissionDenied
    case deviceUnavailable
    case sessionNotRunning
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Izin kamera ditolak. Aktifkan di Pengaturan untuk memindai preparat."
        case .deviceUnavailable:
            return "Kamera tidak tersedia pada perangkat ini."
        case .sessionNotRunning:
            return "Kamera belum siap. Coba tutup dan buka kembali layar pengambilan gambar."
        case .captureFailed:
            return "Gagal mengambil gambar preparat. Silakan coba lagi."
        }
    }
}
