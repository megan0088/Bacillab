import Foundation
import Observation

@Observable
final class ResultViewModel {
    private let sampleRepository: any SampleRepositoryProtocol

    private(set) var sample: Sample
    var notes: String
    var isSaving = false
    var isSaved = false
    var errorMessage: String?

    init(sample: Sample, sampleRepository: any SampleRepositoryProtocol) {
        self.sample = sample
        self.notes = sample.notes
        self.sampleRepository = sampleRepository
    }

    func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            sample.notes = notes
            try await sampleRepository.save(sample)
            isSaved = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
