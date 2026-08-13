import Foundation
import Observation

@Observable
final class AppDependencies {
    let cameraService: any CameraServiceProtocol
    let analysisService: any AnalysisServiceProtocol
    let sampleRepository: any SampleRepositoryProtocol

    init() {
        cameraService = CameraService()
        // Both detectors read every field. ResNet drives the count and the grade; YOLO's
        // figure is carried alongside for comparison only. See `DualDetectorService`.
        analysisService = MultiDetectorService()
        sampleRepository = SampleRepository()
    }
}
