import Foundation

protocol SampleRepositoryProtocol: AnyObject {
    func fetchAll() async throws -> [Sample]
    func save(_ sample: Sample) async throws
    func delete(_ sample: Sample) async throws
}
