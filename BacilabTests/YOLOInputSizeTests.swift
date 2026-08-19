import Testing
import Foundation
import UIKit
@testable import Bacilab

/// Diagnostic: does YOLO still detect once the input is the size a real camera produces?
///
/// The synthetic probe is 1024×1024 — exactly the size YOLO was trained at. A photo from
/// `AVCapturePhotoOutput` is ~3024×4032, which `FieldFraming` crops to a 3024×3024 square
/// before Vision letterboxes it back down to 1024. That round trip is the one thing the
/// simulator never exercises, and the one thing that changed about how YOLO is fed.
struct YOLOInputSizeTests {

    private func probe() throws -> UIImage {
        let url = try #require(
            Bundle(for: SizeBundleMarker.self).url(forResource: "bta-probe", withExtension: "png")
        )
        return try #require(UIImage(data: Data(contentsOf: url)))
    }

    /// Redraws the probe at a larger pixel size, the way a camera photo would arrive.
    private func scaled(_ image: UIImage, to size: CGSize) throws -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return try #require(rendered.jpegData(compressionQuality: 0.95))
    }

    @Test("YOLO tetap mendeteksi pada ukuran asli kamera")
    func yoloDetectsAtCameraResolution() async throws {
        let service = YOLOAnalysisService()
        let image = try probe()

        let native = try await service.analyze(imageData: try scaled(image, to: CGSize(width: 1024, height: 1024)))
        let large = try await service.analyze(imageData: try scaled(image, to: CGSize(width: 3024, height: 3024)))
        let photo = try await service.analyze(imageData: try scaled(image, to: CGSize(width: 3024, height: 4032)))

        // Recorded so a failure names which size broke rather than just "0 detections".
        #expect(native.btaCount > 0, "1024² menghasilkan 0 deteksi")
        #expect(large.btaCount > 0,
                "3024² menghasilkan 0 deteksi (1024² dapat \(native.btaCount)) — ukuran input merusak YOLO")
        #expect(photo.btaCount > 0,
                "3024×4032 menghasilkan 0 deteksi (1024² dapat \(native.btaCount)) — jalur kamera merusak YOLO")
    }

    /// Moved here when this branch dropped the ResNet test file. With a single model the
    /// presence check matters more, not less: it is the only detector, so without it the whole
    /// suite can pass while nothing ever loaded from the bundle.
    @Test("Detektor termuat dari bundle, bukan fallback")
    func detectorIsLoaded() throws {
        #expect(YOLOAnalysisService.isDetectorLoaded,
                "BTADetector.mlmodelc tidak termuat — test lain bisa hijau tanpa model sama sekali")
    }
}

private final class SizeBundleMarker {}
