import Foundation
import Observation

@Observable
final class AppDependencies {
    let cameraService: any CameraServiceProtocol
    let analysisService: any AnalysisServiceProtocol
    let sampleRepository: any SampleRepositoryProtocol

    init() {
        cameraService = CameraService()
        analysisService = VisionAnalysisService()
        sampleRepository = SampleRepository()
    }
}
