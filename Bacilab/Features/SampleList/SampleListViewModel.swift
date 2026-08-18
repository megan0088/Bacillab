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

    /// Whether an empty history should be filled with demo data.
    ///
    /// Off by default so tests get exactly the sessions they set up. `ElectraLabApp` turns it on.
    private let seedsDemoData: Bool

    init(sessionStore: any SessionStoreProtocol, seedsDemoData: Bool = false) {
        self.sessionStore = sessionStore
        self.seedsDemoData = seedsDemoData
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            var loaded = try await sessionStore.allSessions()

            // Seeding is guarded on an empty history inside `DemoSeeder` too, so this can never
            // add demo data on top of real work.
            if seedsDemoData, loaded.isEmpty {
                await DemoSeeder.seedIfEmpty(store: sessionStore)
                loaded = try await sessionStore.allSessions()
            }

            sessions = loaded
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

    /// Search only — the status filter chips are gone.
    ///
    /// Matches the ID card number (NIK), the medical record number and the patient name.
    /// The field is labelled for the ID card because that is what the hi-fi asks for, but
    /// matching the other two costs nothing when unused and spares a technician who types a
    /// name, finds nothing, and concludes the record is missing.
    var filteredSessions: [ExamSession] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return sessions }

        return sessions.filter {
            $0.patient.nationalID.localizedCaseInsensitiveContains(query)
                || $0.patient.medicalRecordNumber.localizedCaseInsensitiveContains(query)
                || $0.patient.name.localizedCaseInsensitiveContains(query)
        }
    }
}
