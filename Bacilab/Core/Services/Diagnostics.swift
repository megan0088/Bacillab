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

extension Diag {

    /// The app's physical memory footprint in MB — the figure jetsam judges when it decides
    /// whether to kill the process.
    ///
    /// Worth having because an out-of-memory kill is invisible from inside: no exception, no
    /// crash report from the app's own code, just an abrupt exit that looks exactly like a
    /// crash. A footprint logged after every field turns "it dies around the twentieth" into a
    /// number that either climbs or does not, which is the difference between a diagnosis and
    /// a guess.
    static var footprintMB: Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 }
        return Double(info.phys_footprint) / 1024 / 1024
    }
}
