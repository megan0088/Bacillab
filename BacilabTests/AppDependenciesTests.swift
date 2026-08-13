import Testing
@testable import Bacilab

struct AppDependenciesTests {

    @Test("Penyimpanan sesi tersedia dari container")
    func sessionStoreIsWired() {
        #expect(AppDependencies().sessionStore is SessionStore)
    }

    @Test("Setiap sesi mendapat antrean analisisnya sendiri")
    @MainActor
    func eachSessionGetsItsOwnQueue() {
        let deps = AppDependencies()
        let a = deps.makeAnalysisQueue()
        let b = deps.makeAnalysisQueue()

        #expect(a !== b,
                "Antrean bersama akan mencampur lapang dari dua sesi ke dalam satu urutan")
    }
}
