import Foundation

protocol AnalysisServiceProtocol: AnyObject {
    func analyze(imageData: Data) async throws -> AnalysisResult

    /// Analyse a field using only the chosen model(s).
    ///
    /// Services that own a single model ignore the selection — there is nothing to choose —
    /// so the default implementation below just forwards. Only `DualDetectorService`
    /// implements this meaningfully.
    func analyze(imageData: Data, using selection: DetectorSelection) async throws -> AnalysisResult
}

extension AnalysisServiceProtocol {
    func analyze(imageData: Data, using selection: DetectorSelection) async throws -> AnalysisResult {
        try await analyze(imageData: imageData)
    }
}
