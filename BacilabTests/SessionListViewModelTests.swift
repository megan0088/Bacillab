import Testing
import Foundation
@testable import Bacilab

@MainActor
struct SessionListViewModelTests {

    private final class StubStore: SessionStoreProtocol, @unchecked Sendable {
        var sessions: [ExamSession] = []
        var deleted: [UUID] = []
        func allSessions() async throws -> [ExamSession] { sessions }
        func save(_ snapshot: SessionSnapshot) async throws {}
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

    @Test("Tanpa kata kunci, seluruh sesi tampil")
    func emptySearchShowsEverything() async {
        let store = StubStore()
        store.sessions = [
            session(name: "A", mrn: "RM-1", status: .scanning),
            session(name: "B", mrn: "RM-2", status: .published, grade: .negative),
            session(name: "C", mrn: "RM-3", status: .published, grade: .plus2)
        ]
        let vm = SampleListViewModel(sessionStore: store)
        await vm.load()

        #expect(vm.filteredSessions.count == 3)

        // Spasi saja bukan kata kunci — kalau ia menyaring, daftar mendadak kosong tanpa
        // sebab yang terlihat.
        vm.searchText = "   "
        #expect(vm.filteredSessions.count == 3)
    }

    @Test("Pencarian cocok pada NIK, nomor rekam medis, maupun nama")
    func searchMatchesIDCardMRNAndName() async {
        let store = StubStore()
        let ahmad = session(name: "Ahmad Rizki", mrn: "RM 240724-001", status: .published)
        ahmad.patient.nationalID = "3204012509900001"
        let siti = session(name: "Siti Rahma", mrn: "RM 240724-002", status: .published)
        siti.patient.nationalID = "3204014403950002"
        store.sessions = [ahmad, siti]

        let vm = SampleListViewModel(sessionStore: store)
        await vm.load()

        // Kolomnya berlabel nomor KTP, jadi ini yang paling utama harus cocok.
        vm.searchText = "3204014403950002"
        #expect(vm.filteredSessions.map(\.patient.name) == ["Siti Rahma"])

        vm.searchText = "240724-001"
        #expect(vm.filteredSessions.map(\.patient.name) == ["Ahmad Rizki"])

        vm.searchText = "ahmad"
        #expect(vm.filteredSessions.count == 1,
                "Mengetik nama harus tetap menemukan — kalau tidak, petugas mengira datanya hilang")
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
