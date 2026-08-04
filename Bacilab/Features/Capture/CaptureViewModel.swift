import AVFoundation
import Foundation
import Observation

@Observable
final class CaptureViewModel {
    private let cameraService: any CameraServiceProtocol
    private let analysisService: any AnalysisServiceProtocol

    var isCapturing = false
    var errorMessage: String?

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

            // Store the last captured frame
            if !imageData.isEmpty {
                draft.imageData = imageData
            }

            // Run AI detection on this field and accumulate BTA count
            if !imageData.isEmpty {
                let result = try await analysisService.analyze(imageData: imageData)
                draft.manualBTACount += result.btaCount
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        draft.capturedFieldCount += 1

        // Recalculate grade based on accumulated count across all scanned fields
        draft.grade = BTAGrade.grade(for: draft.manualBTACount, across: draft.capturedFieldCount)
    }
}
