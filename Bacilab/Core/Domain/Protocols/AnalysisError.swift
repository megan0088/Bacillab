import Foundation

/// Failures any detector can report.
///
/// This lived inside `ResNetAnalysisService` until a single-model branch deleted that file and
/// took the error type with it, breaking `MultiDetectorService` and everything downstream. The
/// error is part of the detector *contract*, not of one implementation, so it belongs beside
/// `AnalysisServiceProtocol` where every branch keeps it.
enum AnalysisError: LocalizedError {
    case invalidImage
    case modelUnavailable
    case inferenceFailure(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "The image is invalid or could not be processed."
        case .modelUnavailable:
            return "The BTA detection model could not be loaded, so no count can be produced."
        case .inferenceFailure(let msg):
            return "Detection failed to run: \(msg)"
        }
    }
}
