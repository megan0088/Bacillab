import CoreML
import UIKit
import Vision

private let yolo11Log = Diag("yolo11")

/// The third detector: YOLO11 exported end-to-end, running through CoreML.
///
/// Source: `AI TBC/Model Jess/bestYOLO11Uganda.mlpackage`, bundled as `BTADetectorV11`.
/// Single class `AFB`, trained on the Uganda set, converted 2026-08-10 from torch 2.8.
///
/// Comparison only — `MultiDetectorService` never lets its count reach the grade unless the
/// analyst picks it deliberately.
final class YOLO11AnalysisService: AnalysisServiceProtocol {

    /// The model's declared input is a 640×640 image, **not** the 1024 of the OBB export.
    /// Vision does the resize; this constant is only needed to un-normalise the boxes.
    private static let inputSide: Float = 640

    /// `end2end: True` in the export metadata: the head is one-to-one, so it emits a fixed
    /// 300 rows that are **already** deduplicated. Running NMS over them — as the OBB service
    /// must — would delete genuine neighbouring bacilli. The padding rows are filtered by
    /// score instead.
    private static let maxDetections = 300

    /// Ultralytics' default. Like the OBB model's 0.25, this was never clinically calibrated;
    /// it is one of the things the three-way comparison is meant to expose.
    private let confidenceThreshold: Float = 0.25

    private static let vnModel: VNCoreMLModel? = {
        guard let url = Bundle.main.url(forResource: "BTADetectorV11", withExtension: "mlmodelc") else {
            yolo11Log.error("BTADetectorV11.mlmodelc tidak ada di bundle")
            return nil
        }
        do {
            let mlModel = try MLModel(contentsOf: url, configuration: MLModelConfiguration())
            let vnModel = try VNCoreMLModel(for: mlModel)
            yolo11Log.note("model dimuat: \(url.lastPathComponent)")
            return vnModel
        } catch {
            yolo11Log.error("gagal memuat model: \(error.localizedDescription)")
            return nil
        }
    }()

    static var isDetectorLoaded: Bool { vnModel != nil }

    func analyze(imageData: Data) async throws -> AnalysisResult {
        guard let uiImage = UIImage(data: imageData),
              let cgImage = FieldFraming.uprightCenteredSquare(of: uiImage) else {
            throw AnalysisError.invalidImage
        }

        guard let model = Self.vnModel else {
            throw AnalysisError.modelUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { [weak self] request, error in
                guard let self else { return }

                if let error {
                    continuation.resume(throwing: AnalysisError.inferenceFailure(error.localizedDescription))
                    return
                }

                guard
                    let observation = request.results?.first as? VNCoreMLFeatureValueObservation,
                    let tensor = observation.featureValue.multiArrayValue
                else {
                    let kinds = (request.results ?? []).map { String(describing: type(of: $0)) }
                    yolo11Log.error("output tak dikenali, hasil: \(kinds.description)")
                    continuation.resume(throwing: AnalysisError.inferenceFailure(
                        "Output model tidak dikenali."))
                    return
                }

                let (count, confidence, boxes) = self.decode(tensor)
                yolo11Log.note("hasil akhir: \(count) deteksi, conf \(confidence)")

                continuation.resume(returning: AnalysisResult(
                    btaCount: count,
                    confidence: confidence,
                    grade: BTAGrade.grade(for: count, across: 1),
                    analyzedAt: Date(),
                    detectedBoxes: boxes
                ))
            }
            // The input is already the square crop, so fit and fill coincide; `.scaleFit`
            // keeps it identical to how the other CoreML detector is fed.
            request.imageCropAndScaleOption = .scaleFit

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: AnalysisError.inferenceFailure(error.localizedDescription))
            }
        }
    }

    // MARK: - End-to-end decoding

    /// Turns the `(1, 300, 6)` end-to-end tensor into a count and boxes.
    ///
    /// Row layout: `x1, y1, x2, y2, score, class` — corners, not centre/size, and in pixels
    /// of the 640 input. Unused slots are zero-filled, which the score cutoff discards.
    private func decode(_ tensor: MLMultiArray) -> (count: Int, confidence: Double, boxes: [DetectedBox]) {
        guard tensor.shape.count == 3, tensor.shape[2].intValue == 6 else {
            yolo11Log.error("bentuk tensor tak terduga: \(tensor.shape.map(\.intValue).description)")
            return (0, 0, [])
        }
        let rows = min(tensor.shape[1].intValue, Self.maxDetections)
        guard rows > 0, tensor.dataType == .float32 else {
            yolo11Log.error("rows=\(rows) dtype=\(tensor.dataType.rawValue) — bukan float32?")
            return (0, 0, [])
        }

        let base = tensor.dataPointer.bindMemory(to: Float.self, capacity: rows * 6)
        let rowStride = tensor.strides[1].intValue
        let colStride = tensor.strides[2].intValue

        func value(_ row: Int, _ column: Int) -> Float {
            base[row * rowStride + column * colStride]
        }

        var boxes: [DetectedBox] = []
        var scoreTotal: Float = 0
        var rawMax: Float = 0

        for row in 0..<rows {
            let score = value(row, 4)
            guard score >= confidenceThreshold else { continue }

            let x1 = value(row, 0), y1 = value(row, 1)
            let x2 = value(row, 2), y2 = value(row, 3)
            rawMax = max(rawMax, max(x2, y2))

            let width = (x2 - x1) / Self.inputSide
            let height = (y2 - y1) / Self.inputSide
            guard width > 0, height > 0 else { continue }

            boxes.append(DetectedBox(
                cx: ((x1 + x2) / 2) / Self.inputSide,
                cy: ((y1 + y2) / 2) / Self.inputSide,
                w: width,
                h: height,
                // The Detect head is axis-aligned; there is no orientation to report.
                angle: 0
            ))
            scoreTotal += score
        }

        // If the export ever switches to normalised corners this would silently shrink every
        // box by 640× rather than fail, so say so instead of drawing invisible rectangles.
        if !boxes.isEmpty && rawMax <= 1.5 {
            yolo11Log.error("koordinat maks \(rawMax) — tampaknya sudah ternormalisasi, bukan piksel 640")
        }

        guard !boxes.isEmpty else { return (0, 0, []) }
        return (boxes.count, Double(scoreTotal) / Double(boxes.count), boxes)
    }
}
