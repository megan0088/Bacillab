import CoreGraphics
import Foundation

private let resnetLog = Diag("resnet")
// @preconcurrency: ORTSession is not annotated Sendable, but ONNX Runtime documents a
// session as safe to Run concurrently, and here it is created once and only ever read.
@preconcurrency import OnnxRuntimeBindings
import UIKit

// Errors that can be thrown during BTA analysis
enum AnalysisError: LocalizedError {
    case invalidImage
    case modelUnavailable
    case inferenceFailure(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "The image is invalid or could not be processed."
        case .modelUnavailable:
            return "The BTA detection model could not be loaded, so no count can be produced."
        case .inferenceFailure(let msg):
            return "Detection failed to run: \(msg)"
        }
    }
}

final class ResNetAnalysisService: AnalysisServiceProtocol {

    // BTADetector.onnx is fold 4 of the 5-fold run in `runs/`: a torchvision
    // Faster R-CNN ResNet50-FPN (2 classes, background + AFB) exported with the whole
    // detection pipeline inside the graph — GeneralizedRCNNTransform, RPN, ROIAlign and
    // class NMS all run in ONNX Runtime. Swift hands over raw pixels and reads boxes back.
    //
    // Not CoreML, and not for lack of trying: Faster R-CNN has data-dependent control flow
    // (score filtering, top-k proposals, a variable NMS output length). `torch.jit.trace`
    // bakes one sample's counts in as constants and then silently returns that same count
    // for every slide; `torch.jit.script` keeps the control flow but coremltools cannot
    // convert the result. ONNX is the export that preserves the real pipeline.
    private static let session: ORTSession? = {
        guard let path = Bundle.main.path(forResource: "BTADetector", ofType: "onnx") else {
            return nil
        }
        return try? ORTSession(env: env, modelPath: path, sessionOptions: nil)
    }()

    private static let env: ORTEnv = {
        // force-try: ORTEnv only fails if the runtime itself cannot start, in which case
        // nothing below could work either.
        try! ORTEnv(loggingLevel: ORTLoggingLevel.warning)
    }()

    /// Whether the bundled Faster R-CNN actually loaded.
    ///
    /// Exists for the tests: without it a suite could pass while the detector was never
    /// there. Nothing in the app should branch on this — `analyze` throws
    /// `.modelUnavailable` rather than degrade, and that is the only correct response.
    static var isDetectorLoaded: Bool { session != nil }

    // A full field takes seconds on device, so keep it off the cooperative pool.
    private static let inferenceQueue = DispatchQueue(label: "id.klinikbunda.bacilab.inference",
                                                      qos: .userInitiated)

    /// The score cutoff and NMS IoU are **compiled into the graph**, not applied here:
    /// `box_score_thresh=0.70`, `box_nms_thresh=0.50`, taken from fold 4's
    /// `calibrated_metrics.json` (the threshold search picked 0.70, giving precision 0.79 /
    /// recall 0.76 / count MAE 1.32 on its validation split). Changing either one means
    /// re-exporting the model — there is no Swift-side knob, deliberately, so the shipped
    /// thresholds always match the ones that were actually measured.
    ///
    /// Those figures come from fold 4's own validation split and are the best of the five
    /// folds; the 5-fold mean is AP50 0.72 / count MAE 1.81. Neither has been checked
    /// against slides read at Electra Lab.
    func analyze(imageData: Data) async throws -> AnalysisResult {
        // Pooled: decoding a 1224² JPEG and redrawing it through UIGraphicsImageRenderer leaves
        // several full-frame bitmaps in the autorelease pool. On one field that is invisible; the
        // queue runs twenty back to back, and without a pool of their own they are only released
        // when the enclosing pool drains — which on a cooperative-pool thread is not tied to the
        // loop at all.
        let cgImage: CGImage = try autoreleasepool {
            guard let uiImage = UIImage(data: imageData),
                  let cg = FieldFraming.uprightCenteredSquare(of: uiImage) else {
                throw AnalysisError.invalidImage
            }
            return cg
        }

        // A missing model must be loud. This used to return a stub
        // (`btaCount: 0, grade: .negative`) so the flow would keep working, but that is the
        // single most dangerous thing this file can do: a slide the model never looked at
        // comes back reading *Negatif*, which is the result that sends an infectious patient
        // home untreated. It also let tests go green without the detector ever loading.
        guard let session = Self.session else {
            throw AnalysisError.modelUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            Self.inferenceQueue.async {
                // `detect` builds a 3×1224×1224 Float array (~18 MB) and copies it again into an
                // NSMutableData for ORT. Pooled so that peak belongs to one field rather than
                // accumulating across the queue.
                autoreleasepool {
                    do {
                        continuation.resume(returning: try Self.detect(in: cgImage, using: session))
                    } catch let error as AnalysisError {
                        continuation.resume(throwing: error)
                    } catch {
                        continuation.resume(
                            throwing: AnalysisError.inferenceFailure(error.localizedDescription))
                    }
                }
            }
        }
    }

    // MARK: - Inference

    private static func detect(in cgImage: CGImage, using session: ORTSession) throws -> AnalysisResult {
        guard let planar = planarRGB(from: cgImage) else {
            throw AnalysisError.invalidImage
        }

        // ORTValue does not copy: the caller owns the buffer and it has to outlive the run.
        let inputData = NSMutableData(bytes: planar.pixels,
                                      length: planar.pixels.count * MemoryLayout<Float>.stride)
        let input = try ORTValue(
            tensorData: inputData,
            elementType: ORTTensorElementDataType.float,
            shape: [3, NSNumber(value: planar.height), NSNumber(value: planar.width)]
        )

        // `labels` is deliberately not requested: the model has a single foreground class,
        // so every detection is class 1 (AFB) and the tensor carries no information.
        // `inputData` must stay alive for the whole run: `ORTValue` holds the buffer rather than
        // copying it, and its last syntactic use is the line above — ARC is free to release it
        // before `run` finishes, which would have the model read freed memory. The behaviour
        // would depend on allocator timing, so it would fail intermittently rather than always.
        let outputs = try withExtendedLifetime(inputData) {
            try session.run(
                withInputs: ["image": input],
                outputNames: ["boxes", "scores"],
                runOptions: nil
            )
        }

        guard let boxesValue = outputs["boxes"], let scoresValue = outputs["scores"] else {
            throw AnalysisError.inferenceFailure("Output model tidak dikenali.")
        }

        let scores = try floats(from: scoresValue.tensorData())
        let boxCoords = try floats(from: boxesValue.tensorData())

        // Each box is x1, y1, x2, y2 in the pixel space of the image we fed in.
        let count = min(scores.count, boxCoords.count / 4)
        guard count > 0 else {
            return AnalysisResult(btaCount: 0, confidence: 0, grade: .negative, analyzedAt: Date())
        }

        let width = Float(planar.width)
        let height = Float(planar.height)
        let boxes = (0..<count).map { i -> DetectedBox in
            let x1 = boxCoords[i * 4], y1 = boxCoords[i * 4 + 1]
            let x2 = boxCoords[i * 4 + 2], y2 = boxCoords[i * 4 + 3]
            return DetectedBox(
                cx: ((x1 + x2) / 2) / width,
                cy: ((y1 + y2) / 2) / height,
                w: (x2 - x1) / width,
                h: (y2 - y1) / height,
                // Faster R-CNN boxes are axis-aligned. The previous detector was YOLO-OBB
                // and `DetectedBox.angle` survives for it; there is no rotation to report.
                angle: 0
            )
        }

        let averageConfidence = Double(scores.prefix(count).reduce(0, +)) / Double(count)
        resnetLog.note("input \(planar.width)x\(planar.height) -> \(count) deteksi, conf \(averageConfidence)")

        return AnalysisResult(
            btaCount: count,
            confidence: averageConfidence,
            grade: BTAGrade.grade(for: count, across: 1),
            analyzedAt: Date(),
            detectedBoxes: boxes
        )
    }

    private static func floats(from data: NSMutableData) -> [Float] {
        [Float](unsafeUninitializedCapacity: data.length / MemoryLayout<Float>.stride) { buffer, filled in
            filled = data.length / MemoryLayout<Float>.stride
            _ = data.copyBytes(to: buffer)
        }
    }

    // MARK: - Input framing

    /// Unpacks a `CGImage` into the planar RGB float tensor the graph expects: shape
    /// (3, H, W), channel-first, values in 0...1. The ImageNet mean/std normalisation is
    /// inside the graph, so it must *not* be applied here as well.
    private static func planarRGB(from cgImage: CGImage) -> (pixels: [Float], width: Int, height: Int)? {
        let width = cgImage.width
        let height = cgImage.height
        let pixelCount = width * height
        guard pixelCount > 0 else { return nil }

        var rgba = [UInt8](repeating: 0, count: pixelCount * 4)
        guard let context = rgba.withUnsafeMutableBytes({ raw -> CGContext? in
            CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        }) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var planar = [Float](repeating: 0, count: pixelCount * 3)
        for i in 0..<pixelCount {
            planar[i] = Float(rgba[i * 4]) / 255
            planar[pixelCount + i] = Float(rgba[i * 4 + 1]) / 255
            planar[pixelCount * 2 + i] = Float(rgba[i * 4 + 2]) / 255
        }

        return (planar, width, height)
    }
}
