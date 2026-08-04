import Foundation

protocol AnalysisServiceProtocol: AnyObject {
    func analyze(imageData: Data) async throws -> AnalysisResult
}
