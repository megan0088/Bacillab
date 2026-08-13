import Testing
import Foundation
import CoreML
import Vision
import UIKit
@testable import Bacilab

/// Reads YOLO11's raw output without going through the service, to tell two very different
/// things apart: the model scoring everything below the cutoff on this particular image, or
/// the decoder misreading the tensor so that everything gets discarded.
///
/// Both produce "0 detections", and nothing downstream can distinguish them.
struct YOLO11RawTensorTests {

    private func rawOutput() async throws -> MLMultiArray {
        let url = try #require(
            Bundle(for: RawBundleMarker.self).url(forResource: "bta-probe", withExtension: "png")
        )
        let image = try #require(UIImage(data: try Data(contentsOf: url)))
        let square = try #require(FieldFraming.uprightCenteredSquare(of: image))

        let modelURL = try #require(Bundle.main.url(forResource: "BTADetectorV11", withExtension: "mlmodelc"))
        let vnModel = try VNCoreMLModel(for: try MLModel(contentsOf: modelURL))

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNCoreMLRequest(model: vnModel) { request, error in
                if let error { continuation.resume(throwing: error); return }
                guard let obs = request.results?.first as? VNCoreMLFeatureValueObservation,
                      let tensor = obs.featureValue.multiArrayValue else {
                    continuation.resume(throwing: AnalysisError.inferenceFailure("no tensor"))
                    return
                }
                continuation.resume(returning: tensor)
            }
            request.imageCropAndScaleOption = .scaleFit
            do {
                try VNImageRequestHandler(cgImage: square, options: [:]).perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    @Test("Tensor mentah YOLO11 terbaca dan skalanya masuk akal")
    func rawTensorIsReadable() async throws {
        let tensor = try await rawOutput()
        #expect(tensor.shape.map(\.intValue) == [1, 300, 6])

        let rows = tensor.shape[1].intValue
        let rowStride = tensor.strides[1].intValue
        let colStride = tensor.strides[2].intValue
        let base = tensor.dataPointer.bindMemory(to: Float.self, capacity: rows * 6)
        func value(_ r: Int, _ c: Int) -> Float { base[r * rowStride + c * colStride] }

        var maxScore: Float = 0
        var maxCoord: Float = 0
        var nonZeroRows = 0
        for r in 0..<rows {
            let score = value(r, 4)
            maxScore = max(maxScore, score)
            for c in 0..<4 { maxCoord = max(maxCoord, value(r, c)) }
            if value(r, 2) > 0 || value(r, 3) > 0 { nonZeroRows += 1 }
        }

        // A tensor of all zeros means the decode never had anything to work with — a very
        // different problem from low scores on a hard image.
        #expect(nonZeroRows > 0,
                "Seluruh 300 baris kosong — model tidak menghasilkan kandidat sama sekali")

        // The decoder divides by 640. If the export emitted normalised corners this would be
        // ≤1 and every box would be drawn 640× too small instead of failing.
        #expect(maxCoord > 1.5,
                "Koordinat maks \(maxCoord) — sudah ternormalisasi, pembagi 640 di decoder salah")
        #expect(maxCoord <= 640 * 1.05,
                "Koordinat maks \(maxCoord) melebihi sisi input 640 — asumsi ruang piksel salah")

        // Reported so the number is on the record either way; the service's cutoff is 0.25.
        #expect(maxScore >= 0,
                "skor maks \(maxScore), baris berisi \(nonZeroRows), koordinat maks \(maxCoord)")
    }

    @Test("Skor tertinggi menjelaskan mengapa hitungannya nol atau tidak")
    func topScoreExplainsTheCount() async throws {
        let tensor = try await rawOutput()
        let rows = tensor.shape[1].intValue
        let rowStride = tensor.strides[1].intValue
        let colStride = tensor.strides[2].intValue
        let base = tensor.dataPointer.bindMemory(to: Float.self, capacity: rows * 6)

        let scores = (0..<rows).map { base[$0 * rowStride + 4 * colStride] }
        let maxScore = scores.max() ?? 0
        let above = scores.filter { $0 >= 0.25 }.count

        let service = try await YOLO11AnalysisService().analyze(
            imageData: try Data(contentsOf: #require(
                Bundle(for: RawBundleMarker.self).url(forResource: "bta-probe", withExtension: "png")
            ))
        )

        // The service must agree with the raw tensor. If it does, a count of 0 is the model's
        // honest verdict on this synthetic image, not a decoding fault.
        #expect(service.btaCount == above,
                "Service menghitung \(service.btaCount) tapi \(above) baris lolos ambang 0.25 (skor maks \(maxScore))")
    }
}

private final class RawBundleMarker {}
