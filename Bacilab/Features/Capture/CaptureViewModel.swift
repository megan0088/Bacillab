import AVFoundation
import Foundation
import Observation

@Observable
final class CaptureViewModel {
    private let cameraService: any CameraServiceProtocol
    private let analysisService: any AnalysisServiceProtocol

    var isCapturing = false
    var errorMessage: String?
    var permissionDenied = false

    var session: AVCaptureSession { cameraService.session }

    init(
        cameraService: any CameraServiceProtocol,
        analysisService: any AnalysisServiceProtocol,
        sampleRepository: any SampleRepositoryProtocol
    ) {
        self.cameraService = cameraService
        self.analysisService = analysisService
    }

    func startCamera() async {
        do {
            try await cameraService.startSession()
        } catch CameraError.permissionDenied {
            // Distinct from a plain failure: nothing the analyst does on this screen
            // will fix it, so the alert has to point them at Settings instead.
            permissionDenied = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopCamera() {
        cameraService.stopSession()
    }

    // Captures one microscope field: photographs it, runs BTA detection,
    // and accumulates the count on the shared draft.
    func capture(into draft: SampleDraft) async {
        isCapturing = true
        defer { isCapturing = false }

        do {
            let imageData = try await cameraService.captureImage()
            guard !imageData.isEmpty else { throw CameraError.captureFailed }

            // Store the last captured frame
            draft.imageData = imageData

            // Run AI detection on this field and accumulate BTA count
            let result = try await analysisService.analyze(imageData: imageData)
            draft.manualBTACount += result.btaCount

            // Running mean of per-field detection confidence. capturedFieldCount is
            // still the count *before* this field, so it doubles as the divisor.
            let analysedSoFar = Double(draft.capturedFieldCount)
            draft.aiConfidence =
                (draft.aiConfidence * analysedSoFar + result.confidence) / (analysedSoFar + 1)

            // Only a field that was actually photographed and analysed counts. Counting
            // a failed capture would inflate the denominator and drag the grade down.
            draft.capturedFieldCount += 1

            if !draft.hasManualGrade {
                draft.grade = BTAGrade.grade(for: draft.manualBTACount, across: draft.capturedFieldCount)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
