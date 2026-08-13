import Foundation
import OSLog

/// Logging that is visible both in production and on an attached console.
///
/// `os.Logger` alone goes only to the unified log, which `devicectl … --console` does not
/// relay — it forwards stdout/stderr. A device-only bug instrumented with `Logger` therefore
/// produces a completely silent console and reads as "the code never ran", which is exactly
/// the wrong conclusion to hand someone mid-debug. Writing to both keeps proper structured
/// logging for the field while making an attached console genuinely useful.
///
/// The stderr copy is Debug-only, so release builds carry the unified log alone.
struct Diag {
    private let logger: Logger
    private let tag: String

    init(_ category: String) {
        self.logger = Logger(subsystem: "id.klinikbunda.bacilab", category: category)
        self.tag = category
    }

    func note(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        emit("note", message)
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        emit("ERROR", message)
    }

    private func emit(_ level: String, _ message: String) {
        #if DEBUG
        FileHandle.standardError.write(Data("[\(tag)] \(level): \(message)\n".utf8))
        #endif
    }
}
