import Testing
import Foundation
import CoreML
import UIKit
@testable import Bacilab

/// Guards the hand-written YOLO-OBB decoding in `VisionAnalysisService`.
///
/// `bta-probe.png` is a synthetic 1024x1024 field of rod-shaped marks — not a real
/// slide. Its only job is to be a fixed input with a known answer: running the same
/// model through ultralytics' own OBB postprocess on this image yields 105 detections,
/// and the bundled fp16 export lands within a couple of counts of that. A drift here
/// means the tensor layout, the ProbIoU maths, or the NMS ordering broke.
struct BTADetectorTests {

    private func probeImageData() throws -> Data {
        let url = try #require(
            Bundle(for: BundleMarker.self).url(forResource: "bta-probe", withExtension: "png"),
            "bta-probe.png tidak ada di test bundle"
        )
        return try Data(contentsOf: url)
    }

    @Test("Model BTADetector ikut ter-bundle dan bisa dimuat")
    func modelIsBundled() throws {
        let url = try #require(
            Bundle.main.url(forResource: "BTADetector", withExtension: "mlmodelc"),
            "BTADetector.mlmodelc tidak ada di app bundle"
        )
        let model = try MLModel(contentsOf: url)
        let outputs = model.modelDescription.outputDescriptionsByName

        #expect(model.modelDescription.inputDescriptionsByName["image"] != nil)
        let shape = try #require(outputs.values.first?.multiArrayConstraint?.shape)
        #expect(shape.map(\.intValue) == [1, 6, 21504],
                "Bentuk output berubah — decoder perlu disesuaikan")
    }

    @Test("Deteksi pada probe cocok dengan referensi ultralytics")
    func countMatchesReference() async throws {
        let result = try await VisionAnalysisService().analyze(imageData: probeImageData())

        // ultralytics (fp32) counts 105 here; fp16 rounding at the 0.25 cutoff moves a
        // couple of borderline candidates either way.
        #expect((100...112).contains(result.btaCount),
                "Dapat \(result.btaCount) BTA, di luar rentang referensi 105±7")
        #expect(result.confidence > 0.25)
        // 105 in a single field extrapolates to 10 500 per 100 fields
        #expect(result.grade == .plus3)
    }

    /// A photo from `AVCapturePhotoOutput` stores its rotation in EXIF rather than in the
    /// pixels. `VNImageRequestHandler(cgImage:)` ignores that, so without the upright
    /// redraw the field would be analysed sideways on every portrait capture — something
    /// the square simulator image can never surface.
    @Test("Foto dengan EXIF rotation memberi hitungan yang sama")
    func rotatedInputMatchesUpright() async throws {
        let service = VisionAnalysisService()
        let base = try #require(UIImage(data: try probeImageData()))
        let cg = try #require(base.cgImage)

        // Both sides go through an identical JPEG round-trip, so the only difference
        // left is the EXIF orientation flag — otherwise compression artefacts around
        // the 0.25 confidence cutoff would show up as a false orientation failure.
        func jpeg(_ orientation: UIImage.Orientation) throws -> Data {
            let image = UIImage(cgImage: cg, scale: base.scale, orientation: orientation)
            return try #require(image.jpegData(compressionQuality: 0.95))
        }

        let upright = try await service.analyze(imageData: try jpeg(.up))
        let afterRotation = try await service.analyze(imageData: try jpeg(.right))

        let drift = abs(afterRotation.btaCount - upright.btaCount)
        #expect(drift <= 8,
                "Hitungan bergeser \(drift) saat gambar diputar (\(upright.btaCount) → \(afterRotation.btaCount)) — orientasi tidak ditangani")
    }
}

/// Anchors `Bundle(for:)` to the test bundle.
private final class BundleMarker {}
