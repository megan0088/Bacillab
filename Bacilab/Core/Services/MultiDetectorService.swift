import Foundation
import OSLog

private let multiLog = Diag("multi")

/// Runs the detector(s) the analyst picked over one field.
///
/// With `.all`, the point of reading one field three times is that the alternative —
/// capturing once per model — cannot work: the microscope drifts and the focus changes
/// between shots, so a difference in counts would be part model and part field, inseparably.
/// Here every model receives the identical `Data`, framed identically by `FieldFraming`, so a
/// disagreement is only ever about the models. Picking a single model is for looking at one
/// in isolation; it is not a way to compare them.
///
/// **The grade follows `selection.gradingDetector`, and nothing else.** With `.all` that is
/// ResNet and the two YOLOs merely ride along; averaging them would produce a count no model
/// actually made. Choosing one on purpose does hand the grade to it — that is what choosing
/// means — so the UI has to name whichever model produced the number on screen.
final class MultiDetectorService: AnalysisServiceProtocol {

    /// One entry per detector. A dictionary rather than three stored properties so adding a
    /// fourth model touches this line and nothing else in the orchestration below.
    private let detectors: [DetectorKind: any AnalysisServiceProtocol]

    /// YOLOv8 is switched off here rather than deleted.
    ///
    /// Only ResNet and YOLO11 ship for now. `DetectorKind.yolo`, `YOLOAnalysisService` and the
    /// bundled `BTADetector.mlmodelc` all remain intact, so turning it back on is uncommenting
    /// one line — and, just as importantly, sessions already saved with YOLOv8 readings still
    /// decode. `analyze` filters on `detectors[$0] != nil`, so an absent entry is simply not run;
    /// nothing else needs to know.
    init(detectors: [DetectorKind: any AnalysisServiceProtocol] = [
        .resnet: ResNetAnalysisService(),
        // .yolo: YOLOAnalysisService(),
        .yolo11: YOLO11AnalysisService(),
    ]) {
        self.detectors = detectors
    }

    func analyze(imageData: Data) async throws -> AnalysisResult {
        try await analyze(imageData: imageData, using: .all)
    }

    func analyze(imageData: Data, using selection: DetectorSelection) async throws -> AnalysisResult {
        // All requested models run concurrently: the two YOLOs are milliseconds against the
        // ResNet's seconds, so the comparison costs the technician essentially nothing beyond
        // the slowest single model.
        let requested = DetectorKind.allCases.filter {
            selection.includes($0) && detectors[$0] != nil
        }

        let outcomes = await withTaskGroup(of: Outcome.self) { group -> [Outcome] in
            for kind in requested {
                guard let service = detectors[kind] else { continue }
                group.addTask { await self.timed(kind) { try await service.analyze(imageData: imageData) } }
            }
            var collected: [Outcome] = []
            for await outcome in group { collected.append(outcome) }
            // Task groups complete out of order; restore a stable order so the columns do
            // not swap places between fields.
            return collected.sorted {
                let all = DetectorKind.allCases
                return all.firstIndex(of: $0.reading.detector)! < all.firstIndex(of: $1.reading.detector)!
            }
        }

        // The grading model's failure is a real failure — there is no result without it.
        // The other model's failure is not: it becomes a reading marked `failure`, so the UI
        // can say the comparison did not run rather than show a zero reading as "saw nothing".
        guard let grading = outcomes.first(where: { $0.reading.detector == selection.gradingDetector }) else {
            throw AnalysisError.modelUnavailable
        }
        guard let result = try grading.result() else {
            throw AnalysisError.modelUnavailable
        }

        // The exact figures the UI receives. Logged here because the models can be provably
        // right while the number on screen is wrong, and this is the boundary between them.
        let summary = outcomes.map { "\($0.reading.detector.rawValue)=\($0.reading.btaCount)" }
        multiLog.note("pilihan=\(selection.rawValue) grade-dari=\(selection.gradingDetector.rawValue) "
                      + "bacaan[\(summary.joined(separator: " "))] btaCount=\(result.btaCount)")

        // Every model is cut to the same circular field of view before anything downstream sees
        // it, so the comparison stays like-for-like and the grading count matches what is drawn.
        let readings = outcomes.map { Self.restrictedToFieldOfView($0.reading) }
        let gradingReading = readings.first { $0.detector == selection.gradingDetector }
        let count = gradingReading?.btaCount ?? result.btaCount

        return AnalysisResult(
            btaCount: count,
            confidence: gradingReading?.confidence ?? result.confidence,
            grade: BTAGrade.grade(for: count, across: 1),
            analyzedAt: result.analyzedAt,
            detectedBoxes: gradingReading?.boxes ?? result.detectedBoxes,
            readings: readings
        )
    }


    // MARK: - Bidang pandang lingkaran

    /// Drops detections whose centre falls outside the inscribed circle.
    ///
    /// The viewfinder and the review canvas both draw the field as a circle, matching the
    /// microscope's own field of view. Restricting the models to that same circle is what keeps
    /// the two honest: **everything counted is visible, and everything visible is counted.**
    /// Masking the display alone would hide roughly 21% of the analysed square while still
    /// counting bacilli inside it — marks the analyst could never check.
    ///
    /// The cost is real and worth stating: about a fifth of each captured square is discarded,
    /// so a slide needs proportionally more fields to reach the same bacilli count, and the
    /// WHO/IUATLD field gates take longer to satisfy.
    ///
    /// A box counts by its centre. Boxes are normalised to the square, so the circle is centred
    /// at (0.5, 0.5) with radius 0.5.
    private static func restrictedToFieldOfView(_ reading: DetectorReading) -> DetectorReading {
        guard reading.failure == nil, !reading.boxes.isEmpty else { return reading }

        let kept = reading.boxes.filter { box in
            let dx = Double(box.cx) - 0.5
            let dy = Double(box.cy) - 0.5
            return dx * dx + dy * dy <= 0.25
        }
        guard kept.count != reading.boxes.count else { return reading }

        // `confidence` is left as the model reported it: it is that model's mean score over the
        // detections it kept, and the per-box scores needed to recompute it over this subset are
        // not carried on a reading. It therefore covers a slightly wider set than `btaCount`.
        return DetectorReading(
            detector: reading.detector,
            btaCount: kept.count,
            confidence: reading.confidence,
            elapsed: reading.elapsed,
            boxes: kept,
            failure: nil
        )
    }

    // MARK: - Timing

    private struct Outcome {
        let reading: DetectorReading
        let value: AnalysisResult?
        let error: Error?

        /// Rethrows the grading detector's failure; `nil` only when there is nothing to report.
        func result() throws -> AnalysisResult? {
            if let error { throw error }
            return value
        }
    }

    private func timed(_ detector: DetectorKind,
                       _ work: @escaping () async throws -> AnalysisResult) async -> Outcome {
        let started = Date()
        do {
            let value = try await work()
            return Outcome(
                reading: DetectorReading(
                    detector: detector,
                    btaCount: value.btaCount,
                    confidence: value.confidence,
                    elapsed: Date().timeIntervalSince(started),
                    boxes: value.detectedBoxes
                ),
                value: value,
                error: nil
            )
        } catch {
            multiLog.error("""
                \(detector.rawValue) gagal setelah \
                \(Date().timeIntervalSince(started))s: \
                \(error.localizedDescription)
                """)
            return Outcome(
                reading: DetectorReading(
                    detector: detector,
                    btaCount: 0,
                    confidence: 0,
                    elapsed: Date().timeIntervalSince(started),
                    failure: error.localizedDescription
                ),
                value: nil,
                error: error
            )
        }
    }
}
