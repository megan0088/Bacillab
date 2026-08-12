import AVFoundation
import Foundation
import Observation

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
    var detectedFlash = false   // briefly true when bacteria found — drives a UI flash

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

                    let result = try await self.analysisService.analyze(imageData: imageData)
                    guard !Task.isCancelled else { break }

                    if result.btaCount > 0 {
                        // Bacteria detected — record this as a positive field
                        draft.imageData = imageData
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

                        // Flash the viewfinder ring so the technician sees detection
                        self.detectedFlash = true
                        try? await Task.sleep(for: .milliseconds(500))
                        self.detectedFlash = false
                    }
                    // If btaCount == 0 the frame is silently discarded — no field counted
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

            let result = try await analysisService.analyze(imageData: imageData)
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
