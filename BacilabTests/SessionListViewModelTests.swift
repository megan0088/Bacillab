import Testing
import Foundation
@testable import Bacilab

@MainActor
struct SessionListViewModelTests {

    private final class StubStore: SessionStoreProtocol, @unchecked Sendable {
        var sessions: [ExamSession] = []
        var deleted: [UUID] = []
        func allSessions() async throws -> [ExamSession] { sessions }
        func save(_ session: ExamSession) async throws {}
        func delete(_ session: ExamSession) async throws { deleted.append(session.id) }
        func writeFieldImage(_ data: Data, fileName: String, for session: ExamSession) throws {}
        func fieldImageURL(fileName: String, for session: ExamSession) -> URL {
            FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        }
    }

    private func session(name: String, mrn: String, status: SessionStatus,
                         grade: BTAGrade? = nil) -> ExamSession {
        let s = ExamSession()
        s.patient.name = name
        s.patient.medicalRecordNumber = mrn
        s.status = status
        if let grade { s.chooseGrade(grade) }
        return s
    }

    @Test("Sesi dimuat dari penyimpanan")
    func loadsSessions() async {
        let store = StubStore()
        store.sessions = [session(name: "A", mrn: "RM-1", status: .published)]
        let vm = SampleListViewModel(sessionStore: store)

        await vm.load()

        #expect(vm.sessions.count == 1)
        #expect(!vm.isLoading)
    }

    @Test("Sesi belum terbit tampil sebagai Berjalan")
    func unpublishedSessionsShowAsRunning() async {
        let store = StubStore()
        store.sessions = [
            session(name: "A", mrn: "RM-1", status: .scanning),
            session(name: "B", mrn: "RM-2", status: .reviewing)
        ]
        let vm = SampleListViewModel(sessionStore: store)
        await vm.load()

        #expect(vm.sessions.allSatisfy { $0.displayStatus == .running },
                "Chip Berjalan harus bisa terisi — yang lama tidak pernah bisa")
    }

    @Test("Filter status menyaring daftar")
    func statusFilterWorks() async {
        let store = StubStore()
        store.sessions = [
            session(name: "A", mrn: "RM-1", status: .scanning),
            session(name: "B", mrn: "RM-2", status: .published, grade: .negative),
            session(name: "C", mrn: "RM-3", status: .published, grade: .plus2)
        ]
        let vm = SampleListViewModel(sessionStore: store)
        await vm.load()

        vm.statusFilter = .running
        #expect(vm.filteredSessions.count == 1)

        vm.statusFilter = .negative
        #expect(vm.filteredSessions.map(\.patient.name) == ["B"])

        vm.statusFilter = .positive
        #expect(vm.filteredSessions.map(\.patient.name) == ["C"])

        vm.statusFilter = nil
        #expect(vm.filteredSessions.count == 3)
    }

    @Test("Pencarian cocok pada nama maupun nomor rekam medis")
    func searchMatchesNameAndMRN() async {
        let store = StubStore()
        store.sessions = [
            session(name: "Ahmad Rizki", mrn: "RM 240724-001", status: .published),
            session(name: "Siti Rahma", mrn: "RM 240724-002", status: .published)
        ]
        let vm = SampleListViewModel(sessionStore: store)
        await vm.load()

        vm.searchText = "ahmad"
        #expect(vm.filteredSessions.count == 1)

        vm.searchText = "240724-002"
        #expect(vm.filteredSessions.map(\.patient.name) == ["Siti Rahma"])
    }

    @Test("Menghapus sesi juga menghapusnya dari daftar")
    func deleteRemovesSession() async {
        let store = StubStore()
        let target = session(name: "A", mrn: "RM-1", status: .scanning)
        store.sessions = [target]
        let vm = SampleListViewModel(sessionStore: store)
        await vm.load()

        await vm.delete(target)

        #expect(store.deleted == [target.id])
        #expect(vm.sessions.isEmpty)
    }
}
