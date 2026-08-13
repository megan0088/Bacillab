import CoreML
import OSLog
import UIKit
import Vision

/// Diagnostics for the CoreML path. Every step that can silently yield a low count logs what
/// it saw, because "few BTA", "the model never ran" and "NMS ate them" look identical from
/// the outside — and on a slide, only one of those is a clinical answer.
private let yoloLog = Diag("yolo")

// One oriented detection, in the model's 1024x1024 input space.
// Angle is in radians; only the geometry NMS needs it, the flow only counts.
private struct OrientedBox {
    let cx, cy, w, h, angle: Float
}

/// The previous detector, kept alongside the ResNet so the two can be compared on the same
/// field. YOLOv8s-OBB, single class `AFB`, trained at 1024×1024, running through CoreML.
///
/// This is **comparison only** — `DualDetectorService` never lets its count reach the grade.
/// Its thresholds (`conf 0.25` / `iou 0.7`) are the model's own training defaults and were
/// never clinically calibrated, which is part of what the comparison is meant to expose.
final class YOLOAnalysisService: AnalysisServiceProtocol {

    // Its head is *not* an NMS pipeline, so Vision cannot emit VNRecognizedObjectObservation
    // for it — the raw (1, 6, 21504) tensor is decoded by hand in `decode` below. Reading
    // `request.results as? [VNRecognizedObjectObservation]` would yield an empty array and
    // report every slide Negatif, silently. Xcode compiles the bundled .mlpackage to
    // .mlmodelc, which is what ships in the app.
    private static let vnModel: VNCoreMLModel? = {
        guard let url = Bundle.main.url(forResource: "BTADetector", withExtension: "mlmodelc") else {
            yoloLog.error("BTADetector.mlmodelc tidak ada di bundle")
            return nil
        }
        do {
            let mlModel = try MLModel(contentsOf: url, configuration: MLModelConfiguration())
            let vnModel = try VNCoreMLModel(for: mlModel)
            yoloLog.note("model dimuat: \(url.lastPathComponent)")
            return vnModel
        } catch {
            // This used to be `try?`, which turned a real load failure into a silent nil and
            // then into an empty comparison column with no way to tell why.
            yoloLog.error("gagal memuat model: \(error.localizedDescription)")
            return nil
        }
    }()

    /// Whether the bundled YOLO model loaded. `DualDetectorService` uses this to record an
    /// honest "did not run" instead of a zero that would read as "saw nothing".
    static var isDetectorLoaded: Bool { vnModel != nil }

    private let confidenceThreshold: Float = 0.25
    private let iouThreshold: Float = 0.7

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
                    yoloLog.error("output tak dikenali, hasil: \(kinds.description)")
                    continuation.resume(throwing: AnalysisError.inferenceFailure(
                        "Output model tidak dikenali."))
                    return
                }

                yoloLog.note("tensor shape=\(tensor.shape.map(\.intValue)) dtype=\(tensor.dataType.rawValue)")

                let (btaCount, avgConfidence, boxes) = self.decode(tensor)
                yoloLog.note("hasil akhir: \(btaCount) deteksi, conf \(avgConfidence)")

                continuation.resume(returning: AnalysisResult(
                    btaCount: btaCount,
                    confidence: avgConfidence,
                    grade: BTAGrade.grade(for: btaCount, across: 1),
                    analyzedAt: Date(),
                    detectedBoxes: boxes
                ))
            }
            // Ultralytics letterboxes its input, so fit the whole frame rather than cropping
            request.imageCropAndScaleOption = .scaleFit

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: AnalysisError.inferenceFailure(error.localizedDescription))
            }
        }
    }

    // MARK: - OBB decoding

    /// Turns the raw (1, 6, anchors) YOLO-OBB tensor into a bacilli count + bounding boxes.
    /// Channel layout per anchor: cx, cy, w, h, score, angle (pixels of 1024 input, radians).
    private func decode(_ tensor: MLMultiArray) -> (count: Int, averageConfidence: Double, boxes: [DetectedBox]) {
        // These two guards are the quiet killers: either one returns 0 with no error, and the
        // UI cannot tell that apart from a genuinely empty field.
        guard tensor.shape.count == 3, tensor.shape[1].intValue == 6 else {
            yoloLog.error("bentuk tensor tak terduga: \(tensor.shape.map(\.intValue).description)")
            return (0, 0, [])
        }
        let anchors = tensor.shape[2].intValue
        guard anchors > 0, tensor.dataType == .float32 else {
            yoloLog.error("anchors=\(anchors) dtype=\(tensor.dataType.rawValue) — bukan float32?")
            return (0, 0, [])
        }

        let base = tensor.dataPointer.bindMemory(to: Float.self, capacity: 6 * anchors)
        let channelStride = tensor.strides[1].intValue
        let anchorStride = tensor.strides[2].intValue

        func value(channel: Int, anchor: Int) -> Float {
            base[channel * channelStride + anchor * anchorStride]
        }

        var boxes: [OrientedBox] = []
        var scores: [Float] = []
        for i in 0..<anchors where value(channel: 4, anchor: i) >= confidenceThreshold {
            boxes.append(OrientedBox(
                cx: value(channel: 0, anchor: i),
                cy: value(channel: 1, anchor: i),
                w: value(channel: 2, anchor: i),
                h: value(channel: 3, anchor: i),
                angle: value(channel: 5, anchor: i)
            ))
            scores.append(value(channel: 4, anchor: i))
        }
        yoloLog.note("lolos ambang \(self.confidenceThreshold): \(boxes.count) dari \(anchors) anchor")
        guard !boxes.isEmpty else { return (0, 0, []) }

        let ranked = zip(boxes, scores).sorted { $0.1 > $1.1 }
        let sortedBoxes  = ranked.map(\.0)
        let sortedScores = ranked.map(\.1)

        let kept = suppress(sortedBoxes)
        guard !kept.isEmpty else { return (0, 0, []) }

        let total = kept.reduce(Float(0)) { $0 + sortedScores[$1] }
        let avgConf = Double(total) / Double(kept.count)

        // Normalize pixel coordinates to [0, 1] for display
        let detectedBoxes = kept.map { i -> DetectedBox in
            let b = sortedBoxes[i]
            return DetectedBox(
                cx: b.cx / 1024,
                cy: b.cy / 1024,
                w:  b.w  / 1024,
                h:  b.h  / 1024,
                angle: b.angle
            )
        }

        return (kept.count, avgConf, detectedBoxes)
    }

    /// Rotated NMS over score-sorted boxes. Mirrors ultralytics' `nms_rotated`: a box is
    /// dropped when *any* higher-scoring box overlaps it — including one already dropped.
    private func suppress(_ boxes: [OrientedBox]) -> [Int] {
        var kept: [Int] = []
        for j in boxes.indices {
            var overlapped = false
            for i in 0..<j where probIoU(boxes[i], boxes[j]) >= iouThreshold {
                overlapped = true
                break
            }
            if !overlapped { kept.append(j) }
        }
        return kept
    }

    /// Probabilistic IoU: treats each oriented box as a Gaussian and compares them via
    /// the Bhattacharyya distance. This is the overlap measure YOLO-OBB is trained with.
    private func probIoU(_ a: OrientedBox, _ b: OrientedBox) -> Float {
        let eps: Float = 1e-7

        func covariance(_ box: OrientedBox) -> (Float, Float, Float) {
            let vx = box.w * box.w / 12
            let vy = box.h * box.h / 12
            let cos = cosf(box.angle), sin = sinf(box.angle)
            return (vx * cos * cos + vy * sin * sin,
                    vx * sin * sin + vy * cos * cos,
                    (vx - vy) * cos * sin)
        }

        let (a1, b1, c1) = covariance(a)
        let (a2, b2, c2) = covariance(b)
        let dx = b.cx - a.cx, dy = a.cy - b.cy

        let den = (a1 + a2) * (b1 + b2) - (c1 + c2) * (c1 + c2)
        let t1 = ((a1 + a2) * dy * dy + (b1 + b2) * dx * dx) / (den + eps) * 0.25
        let t2 = ((c1 + c2) * dx * dy) / (den + eps) * 0.5
        let d1 = max(a1 * b1 - c1 * c1, 0), d2 = max(a2 * b2 - c2 * c2, 0)
        let t3 = log(den / (4 * sqrt(d1) * sqrt(d2) + eps) + eps) * 0.5

        let bd = min(max(t1 + t2 + t3, eps), 100)
        return 1 - sqrt(1 - exp(-bd) + eps)
    }
}
