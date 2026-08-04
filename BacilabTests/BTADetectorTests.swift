import Testing
import Foundation
import CoreML
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
}

/// Anchors `Bundle(for:)` to the test bundle.
private final class BundleMarker {}
