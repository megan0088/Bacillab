import Testing
@testable import Bacilab

struct AppDependenciesTests {

    @Test("Penyimpanan sesi tersedia dari container")
    func sessionStoreIsWired() {
        #expect(AppDependencies().sessionStore is SessionStore)
    }

    @Test("Sesi yang sama selalu mendapat antrean yang sama")
    @MainActor
    func sameSessionReusesItsQueue() {
        let deps = AppDependencies()
        let session = ExamSession()

        #expect(deps.queue(for: session) === deps.queue(for: session),
                "Mencetak antrean baru tiap permintaan membuat dua pekerja menggilas sesi yang sama")
    }

    @Test("Sesi berbeda mendapat antrean berbeda")
    @MainActor
    func differentSessionsGetDifferentQueues() {
        let deps = AppDependencies()

        #expect(deps.queue(for: ExamSession()) !== deps.queue(for: ExamSession()),
                "Antrean bersama akan mencampur lapang dari dua sesi ke dalam satu urutan")
    }
}
