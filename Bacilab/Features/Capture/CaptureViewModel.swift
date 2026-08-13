import AVFoundation
import Foundation
import Observation
import UIKit

private let uiLog = Diag("overlay")

@Observable
final class CaptureViewModel {
    private let cameraService: any CameraServiceProtocol
    private let analysisService: any AnalysisServiceProtocol

    // Manual capture state
    var isCapturing = false
    var errorMessage: String?
    var permissionDenied = false

    // Auto-scan state
    var isAutoScanning = false
    var detectedFlash = false       // briefly true when bacteria found — drives a UI flash

    // Live bounding boxes from the last analyzed frame, for overlay rendering
    var latestDetections: [DetectedBox] = []

    /// What each detector made of the most recent field, for the side-by-side readout and
    /// for drawing each model's own boxes. Only the grading model's figure reaches the draft.
    var latestReadings: [DetectorReading] = []

    /// The exact pixels the models were given, kept so the boxes can be drawn on them.
    ///
    /// Without this the overlay sits on the *live* preview, which has moved on: the analyst
    /// is shown boxes pinned to bacilli that are no longer under them, or to empty field if
    /// the slide was nudged. Boxes over a frame nobody analysed are worse than no boxes —
    /// they invite checking the model's work against the wrong image.
    ///
    /// This is the centred square from `FieldFraming`, not the raw photo, because that is
    /// what the detectors saw and what the box coordinates are normalised against.
    var analyzedImage: UIImage?

    /// Drops the frozen frame and returns the viewfinder to live camera.
    func resumeLivePreview() {
        analyzedImage = nil
        latestReadings = []
        latestDetections = []
    }

    /// Where fields come from, and it stays put.
    ///
    /// Switching source is a deliberate act, not something a stray tap does: a slide read
    /// half from the eyepiece and half from imported photos pools two acquisitions into one
    /// count, and nothing downstream would reveal it happened.
    var inputSource: FieldSource = .camera

    /// Keeps the frame that was just analysed, framed exactly as the models received it,
    /// and returns a compact JPEG of it for the field history.
    ///
    /// Both come from the same square so the stored thumbnail and the live overlay agree —
    /// box coordinates are normalised against that square, so anything else misplaces them.
    @discardableResult
    private func freeze(_ imageData: Data) -> Data? {
        guard let image = UIImage(data: imageData),
              let square = FieldFraming.uprightCenteredSquare(of: image) else { return nil }

        let framed = UIImage(cgImage: square)
        analyzedImage = framed

        // 640 px is plenty to re-examine a field on a phone, and bounds a 100-field session
        // to a few megabytes rather than a few hundred.
        let side: CGFloat = 640
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let thumb = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
            .image { _ in framed.draw(in: CGRect(x: 0, y: 0, width: side, height: side)) }
        return thumb.jpegData(compressionQuality: 0.8)
    }

    /// Which model(s) read the next captured or imported field.
    ///
    /// `.all` is the only setting that compares fairly — every model gets identical pixels.
    /// Capturing once on one model and again on another compares two different fields,
    /// because the slide moves in between.
    var detectorSelection: DetectorSelection = .all

    var session: AVCaptureSession { cameraService.session }

    private var scanTask: Task<Void, Never>?

    init(
        cameraService: any CameraServiceProtocol,
        analysisService: any AnalysisServiceProtocol,
        sampleRepository: any SampleRepositoryProtocol
    ) {
        self.cameraService = cameraService
        self.analysisService = analysisService
    }

    /// What the overlay is being handed. A count that reaches the draft while the box array
    /// is empty means the models are fine and the drawing is not — the two failures look
    /// identical on screen.
    private static func overlaySummary(_ readings: [DetectorReading]) -> String {
        readings
            .map { "\($0.detector.rawValue): \($0.btaCount) hitungan / \($0.boxes.count) kotak" }
            .joined(separator: " | ")
    }

    // MARK: - Camera lifecycle

    func startCamera() async {
        do {
            try await cameraService.startSession()
        } catch CameraError.permissionDenied {
            permissionDenied = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopCamera() {
        stopAutoScan()
        cameraService.stopSession()
    }

    // MARK: - Auto-scan

    // Toggles the continuous scan loop. While running, the app grabs a frame every
    // ~1.5 s, asks the AI model whether bacteria are present, and only counts it as
    // a field when the model returns btaCount > 0. Empty frames are discarded so
    // the technician can move the slide freely without inflating the denominator.
    func toggleAutoScan(into draft: SampleDraft) {
        if isAutoScanning { stopAutoScan() } else { startAutoScan(into: draft) }
    }

    private func startAutoScan(into draft: SampleDraft) {
        guard !isAutoScanning else { return }
        isAutoScanning = true

        scanTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled,
                  draft.capturedFieldCount < draft.totalFieldCount {

                // Respect an in-progress manual capture
                if self.isCapturing {
                    try? await Task.sleep(for: .milliseconds(500))
                    continue
                }

                do {
                    let imageData = try await self.cameraService.captureImage()
                    guard !imageData.isEmpty, !Task.isCancelled else { break }

                    let result = try await self.analysisService.analyze(
                        imageData: imageData, using: self.detectorSelection)
                    guard !Task.isCancelled else { break }

                    // Always update the live overlay with whatever was found
                    self.latestDetections = result.detectedBoxes

                    if result.btaCount > 0 {
                        // Bacteria detected — record this as a positive field
                        draft.imageData = imageData
                        draft.reconcileCountSource(with: self.detectorSelection.gradingDetector)
                        draft.manualBTACount += result.btaCount
                        // Same field, same pixels, second opinion. Each model's count is
                        // filed under the model that produced it.
                        self.latestReadings = result.readings
                        let stored = self.freeze(imageData)
                        draft.record(result.readings, image: stored, source: self.inputSource)
                        uiLog.note(Self.overlaySummary(result.readings))

                        let n = Double(draft.capturedFieldCount)
                        draft.aiConfidence =
                            (draft.aiConfidence * n + result.confidence) / (n + 1)

                        draft.capturedFieldCount += 1

                        if !draft.hasManualGrade {
                            draft.grade = BTAGrade.grade(
                                for: draft.manualBTACount,
                                across: draft.capturedFieldCount
                            )
                        }

                        // Flash the viewfinder ring so the technician sees detection
                        self.detectedFlash = true
                        try? await Task.sleep(for: .milliseconds(500))
                        self.detectedFlash = false
                    } else {
                        // No bacteria — clear old boxes so stale detections don't persist
                        self.latestDetections = []
                    }
                } catch {
                    // Single-frame errors don't kill the scan loop
                    if !Task.isCancelled {
                        self.errorMessage = error.localizedDescription
                    }
                }

                // Interval between frames — long enough for the technician to reposition
                try? await Task.sleep(for: .seconds(1.5))
            }

            self.isAutoScanning = false
        }
    }

    func stopAutoScan() {
        scanTask?.cancel()
        scanTask = nil
        isAutoScanning = false
    }

    // MARK: - Gallery image analysis

    // Accepts image data picked from the photo library and runs it through the same
    // AI pipeline as a camera capture. Counts as one field regardless of btaCount,
    // matching the IUATLD field-count requirement — same as manual capture.
    func analyzeGalleryImage(data: Data, into draft: SampleDraft) async {
        guard !isAutoScanning else { return }
        isCapturing = true
        defer { isCapturing = false }

        do {
            draft.imageData = data
            let result = try await analysisService.analyze(imageData: data, using: detectorSelection)
            latestDetections = result.detectedBoxes
            draft.reconcileCountSource(with: detectorSelection.gradingDetector)
            draft.manualBTACount += result.btaCount
            latestReadings = result.readings
            draft.record(result.readings, image: freeze(data), source: .gallery)
            uiLog.note(Self.overlaySummary(result.readings))

            let n = Double(draft.capturedFieldCount)
            draft.aiConfidence =
                (draft.aiConfidence * n + result.confidence) / (n + 1)

            draft.capturedFieldCount += 1

            if !draft.hasManualGrade {
                draft.grade = BTAGrade.grade(
                    for: draft.manualBTACount,
                    across: draft.capturedFieldCount
                )
            }

            if result.btaCount > 0 {
                detectedFlash = true
                try? await Task.sleep(for: .milliseconds(500))
                detectedFlash = false
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Manual capture

    // One manual field: photograph → analyze → accumulate. Always counts regardless
    // of btaCount, matching the IUATLD field-count requirement.
    func capture(into draft: SampleDraft) async {
        guard !isAutoScanning else { return }   // auto mode owns the camera during scans
        isCapturing = true
        defer { isCapturing = false }

        do {
            let imageData = try await cameraService.captureImage()
            guard !imageData.isEmpty else { throw CameraError.captureFailed }

            draft.imageData = imageData

            let result = try await analysisService.analyze(imageData: imageData, using: detectorSelection)
            latestDetections = result.detectedBoxes
            draft.reconcileCountSource(with: detectorSelection.gradingDetector)
            draft.manualBTACount += result.btaCount

            let n = Double(draft.capturedFieldCount)
            draft.aiConfidence =
                (draft.aiConfidence * n + result.confidence) / (n + 1)

            draft.capturedFieldCount += 1

            if !draft.hasManualGrade {
                draft.grade = BTAGrade.grade(
                    for: draft.manualBTACount,
                    across: draft.capturedFieldCount
                )
            }

            latestReadings = result.readings
            draft.record(result.readings, image: freeze(imageData), source: .camera)
            uiLog.note(Self.overlaySummary(result.readings))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
