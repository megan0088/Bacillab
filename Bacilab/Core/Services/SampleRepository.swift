import Foundation

final class SampleRepository: SampleRepositoryProtocol {
    private var samples: [Sample] = []

    func fetchAll() async throws -> [Sample] {
        samples
    }

    func save(_ sample: Sample) async throws {
        if let index = samples.firstIndex(where: { $0.id == sample.id }) {
            samples[index] = sample
        } else {
            samples.append(sample)
        }
    }

    func delete(_ sample: Sample) async throws {
        samples.removeAll { $0.id == sample.id }
    }
}
