import Foundation
import Observation

@Observable
final class SampleListViewModel {
    private let sampleRepository: any SampleRepositoryProtocol

    var samples: [Sample] = []
    var isLoading = false
    var errorMessage: String?

    init(sampleRepository: any SampleRepositoryProtocol) {
        self.sampleRepository = sampleRepository
    }

    func loadSamples() async {
        isLoading = true
        defer { isLoading = false }
        do {
            samples = try await sampleRepository.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ sample: Sample) async {
        do {
            try await sampleRepository.delete(sample)
            await loadSamples()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
