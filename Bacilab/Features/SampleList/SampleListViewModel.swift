import Foundation
import Observation

@MainActor
@Observable
final class SampleListViewModel {
    private let sessionStore: any SessionStoreProtocol

    private(set) var sessions: [ExamSession] = []
    var isLoading = false
    var errorMessage: String?

    var searchText = ""
    var statusFilter: SessionDisplayStatus?

    init(sessionStore: any SessionStoreProtocol) {
        self.sessionStore = sessionStore
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            sessions = try await sessionStore.allSessions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ session: ExamSession) async {
        do {
            try await sessionStore.delete(session)
            sessions.removeAll { $0.id == session.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var filteredSessions: [ExamSession] {
        let byStatus = statusFilter.map { filter in
            sessions.filter { $0.displayStatus == filter }
        } ?? sessions

        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return byStatus }

        // Nomor rekam medis ikut dicari: itu yang tertulis di tabung dan di formulir,
        // dan sering satu-satunya yang dipegang petugas saat mencari hasil.
        return byStatus.filter {
            $0.patient.name.localizedCaseInsensitiveContains(query)
                || $0.patient.medicalRecordNumber.localizedCaseInsensitiveContains(query)
        }
    }
}
