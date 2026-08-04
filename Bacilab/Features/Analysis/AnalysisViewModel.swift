import Foundation
import Observation

@Observable
final class AnalysisViewModel {
    let sampleRepository: any SampleRepositoryProtocol

    init(analysisService: any AnalysisServiceProtocol, sampleRepository: any SampleRepositoryProtocol) {
        self.sampleRepository = sampleRepository
    }
}
