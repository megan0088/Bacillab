import Vision
import CoreML
import UIKit

// Errors that can be thrown during BTA analysis
enum AnalysisError: LocalizedError {
    case invalidImage
    case inferenceFailure(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Gambar tidak valid atau tidak dapat diproses."
        case .inferenceFailure(let msg):
            return "Gagal menjalankan deteksi: \(msg)"
        }
    }
}

// One oriented detection, in the model's 1024x1024 input space.
// Angle is in radians; only the geometry NMS needs it, the flow only counts.
private struct OrientedBox {
    let cx, cy, w, h, angle: Float
}

final class VisionAnalysisService: AnalysisServiceProtocol {

    // BTADetector is a YOLOv8s-OBB export (task=obb, single class "AFB", 1024x1024).
    // Its head is *not* an NMS pipeline, so Vision cannot emit VNRecognizedObjectObservation
    // for it — the raw (1, 6, 21504) tensor is decoded by hand in `decode` below.
    // Xcode compiles the bundled .mlpackage to .mlmodelc, which is what ships in the app.
    private static let vnModel: VNCoreMLModel? = {
        guard
            let url = Bundle.main.url(forResource: "BTADetector", withExtension: "mlmodelc"),
            let mlModel = try? MLModel(contentsOf: url, configuration: MLModelConfiguration()),
            let vnModel = try? VNCoreMLModel(for: mlModel)
        else { return nil }
        return vnModel
    }()

    // Matches the model's training-time defaults. Both are clinical calibration knobs:
    // confidence trades false negatives against false positives, iou decides how close
    // two bacilli may sit before being counted as one.
    private let confidenceThreshold: Float = 0.25
    private let iouThreshold: Float = 0.7

    func analyze(imageData: Data) async throws -> AnalysisResult {
        guard let uiImage = UIImage(data: imageData),
              let cgImage = Self.uprightCenteredSquare(of: uiImage) else {
            throw AnalysisError.invalidImage
        }

        // If no model is bundled, return a stub so the rest of the flow works
        guard let model = Self.vnModel else {
            return AnalysisResult(btaCount: 0, confidence: 0, grade: .negative, analyzedAt: Date())
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
                    continuation.resume(throwing: AnalysisError.inferenceFailure(
                        "Output model tidak dikenali."))
                    return
                }

                let (btaCount, avgConfidence) = self.decode(tensor)

                // Per-field grade: treat each analyzed image as one field
                let grade = BTAGrade.grade(for: btaCount, across: 1)

                continuation.resume(returning: AnalysisResult(
                    btaCount: btaCount,
                    confidence: avgConfidence,
                    grade: grade,
                    analyzedAt: Date()
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

    // MARK: - Input framing

    /// Redraws the photo upright and crops it to the largest centred square.
    ///
    /// Two things go wrong on a real device without this. A photo straight out of
    /// `AVCapturePhotoOutput` carries its rotation in EXIF, which `VNImageRequestHandler`
    /// ignores when handed a bare `CGImage` — the field would be analysed sideways. And
    /// the frame is 4:3, so letterboxing it into the model's 1024x1024 input shrinks
    /// every bacillus well below the ~13px it was trained at. Cropping to the square
    /// that holds the circular microscope field restores the training-time scale.
    /// On the simulator's already-square field this is a no-op beyond the redraw.
    private static func uprightCenteredSquare(of image: UIImage) -> CGImage? {
        let side = min(image.size.width, image.size.height)
        guard side > 0 else { return nil }

        let origin = CGPoint(
            x: (image.size.width - side) / 2,
            y: (image.size.height - side) / 2
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: side, height: side),
            format: format
        )
        // `draw` applies imageOrientation, so what lands in the context is upright
        let square = renderer.image { _ in
            image.draw(at: CGPoint(x: -origin.x, y: -origin.y))
        }
        return square.cgImage
    }

    // MARK: - OBB decoding

    /// Turns the raw (1, 6, anchors) YOLO-OBB tensor into a bacilli count.
    /// Channel layout per anchor: cx, cy, w, h, score, angle.
    private func decode(_ tensor: MLMultiArray) -> (count: Int, averageConfidence: Double) {
        guard tensor.shape.count == 3, tensor.shape[1].intValue == 6 else { return (0, 0) }
        let anchors = tensor.shape[2].intValue
        guard anchors > 0, tensor.dataType == .float32 else { return (0, 0) }

        let base = tensor.dataPointer.bindMemory(to: Float.self, capacity: 6 * anchors)
        // strides are in elements, so they index the flat buffer directly
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
        guard !boxes.isEmpty else { return (0, 0) }

        let ranked = zip(boxes, scores)
            .sorted { $0.1 > $1.1 }
        let sortedBoxes = ranked.map(\.0)
        let sortedScores = ranked.map(\.1)

        let kept = suppress(sortedBoxes)
        guard !kept.isEmpty else { return (0, 0) }

        let total = kept.reduce(Float(0)) { $0 + sortedScores[$1] }
        return (kept.count, Double(total) / Double(kept.count))
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
