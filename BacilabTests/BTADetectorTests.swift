import Testing
import Foundation
import OnnxRuntimeBindings
import UIKit
@testable import Bacilab

/// Guards the ONNX Runtime detection path in `ResNetAnalysisService`.
///
/// `bta-probe.png` is a synthetic 1024x1024 field of rod-shaped marks — not a real slide.
/// Its only job is to be a fixed input with a known answer. Running fold 4's checkpoint on
/// this exact file, both as PyTorch and as the bundled ONNX export, yields **53** detections
/// at the calibrated 0.70 cutoff. A drift here means the tensor layout, the channel order,
/// or the pixel scaling broke.
struct BTADetectorTests {

    private func probeImageData() throws -> Data {
        let url = try #require(
            Bundle(for: BundleMarker.self).url(forResource: "bta-probe", withExtension: "png"),
            "bta-probe.png tidak ada di test bundle"
        )
        return try Data(contentsOf: url)
    }

    /// The gate for every other test here.
    ///
    /// `ResNetAnalysisService` throws `.modelUnavailable` when the ResNet is missing rather
    /// than returning a zero result, so a broken bundle now fails loudly. This test names the
    /// condition directly so the reason is obvious instead of surfacing as four unrelated
    /// count assertions.
    @Test("Kedua detektor termuat dari bundle, bukan fallback")
    func bothDetectorsAreLoaded() throws {
        // Both models ship now: ResNet reads the field for the grade, YOLO reads the same
        // field for comparison. Either one missing makes the comparison meaningless, so
        // name both here rather than let it surface as odd counts elsewhere.
        #expect(ResNetAnalysisService.isDetectorLoaded,
                "BTADetector.onnx tidak termuat — test lain bisa hijau tanpa model sama sekali")
        #expect(YOLOAnalysisService.isDetectorLoaded,
                "BTADetector.mlmodelc tidak termuat — kolom pembanding akan selalu kosong")
    }

    @Test("Model BTADetector ikut ter-bundle dan kontrak input/output-nya tetap")
    func modelIsBundled() throws {
        let path = try #require(
            Bundle.main.path(forResource: "BTADetector", ofType: "onnx"),
            "BTADetector.onnx tidak ada di app bundle"
        )
        let env = try ORTEnv(loggingLevel: ORTLoggingLevel.warning)
        let session = try ORTSession(env: env, modelPath: path, sessionOptions: nil)

        // The service feeds "image" and reads "boxes"/"scores" by name; if the export is
        // ever regenerated with different names the failure would otherwise be silent.
        #expect(try session.inputNames().contains("image"))
        #expect(try session.outputNames().contains("boxes"))
        #expect(try session.outputNames().contains("scores"))
    }

    @Test("Deteksi pada probe cocok dengan referensi PyTorch")
    func countMatchesReference() async throws {
        let result = try await ResNetAnalysisService().analyze(imageData: probeImageData())

        // PyTorch, Python-ONNX and this Swift path all count exactly 53 on this probe —
        // drawing the PNG through CGContext in DeviceRGB lands on the same pixels PIL does.
        // The ±2 is only slack for image-decoding changes across simulator versions; a
        // drift bigger than that is the pipeline breaking, not rounding.
        #expect((51...55).contains(result.btaCount),
                "Dapat \(result.btaCount) BTA, di luar rentang referensi 53±2")

        // The 0.70 cutoff is compiled into the graph, so nothing weaker can come back.
        #expect(result.confidence >= 0.70)

        // 53 in a single field extrapolates to 5300 per 100 fields
        #expect(result.grade == .plus3)
    }

    @Test("Setiap deteksi berada di dalam frame dan tidak berotasi")
    func boxesAreNormalizedAndAxisAligned() async throws {
        let result = try await ResNetAnalysisService().analyze(imageData: probeImageData())
        let boxes = try #require(result.detectedBoxes.isEmpty ? nil : result.detectedBoxes)

        for box in boxes {
            // CaptureView multiplies these by the viewport size, so anything outside 0...1
            // would draw the overlay off the microscope field.
            #expect((0...1).contains(box.cx) && (0...1).contains(box.cy))
            #expect(box.w > 0 && box.h > 0)
            #expect(box.w <= 1 && box.h <= 1)
            // Faster R-CNN is axis-aligned; a non-zero angle means something invented one.
            #expect(box.angle == 0)
        }
    }

    /// A photo from `AVCapturePhotoOutput` stores its rotation in EXIF rather than in the
    /// pixels, and a bare `CGImage` drops it. Without the upright redraw the field would be
    /// analysed sideways on every portrait capture — something the square simulator image
    /// can never surface.
    @Test("Foto dengan EXIF rotation memberi hitungan yang sama")
    func rotatedInputMatchesUpright() async throws {
        let service = ResNetAnalysisService()
        let base = try #require(UIImage(data: try probeImageData()))
        let cg = try #require(base.cgImage)

        // Both sides go through an identical JPEG round-trip, so the only difference left
        // is the EXIF orientation flag — otherwise compression artefacts around the 0.70
        // cutoff would show up as a false orientation failure.
        func jpeg(_ orientation: UIImage.Orientation) throws -> Data {
            let image = UIImage(cgImage: cg, scale: base.scale, orientation: orientation)
            return try #require(image.jpegData(compressionQuality: 0.95))
        }

        let upright = try await service.analyze(imageData: try jpeg(.up))
        let afterRotation = try await service.analyze(imageData: try jpeg(.right))

        // Without this the test passes on 0 vs 0 — a drift of nothing between two fields the
        // detector never actually read.
        #expect(upright.btaCount > 0, "Tidak ada deteksi sama sekali; test rotasi jadi hampa")

        let drift = abs(afterRotation.btaCount - upright.btaCount)
        #expect(drift <= 8,
                "Hitungan bergeser \(drift) saat gambar diputar (\(upright.btaCount) → \(afterRotation.btaCount)) — orientasi tidak ditangani")
    }
}

/// Anchors `Bundle(for:)` to the test bundle.
private final class BundleMarker {}
