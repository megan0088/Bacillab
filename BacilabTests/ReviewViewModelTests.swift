import Testing
import Foundation
@testable import Bacilab

/// Review adalah satu-satunya pemilik hitungan dan grade. Yang diuji: koreksi tersimpan
/// tanpa langkah tambahan, dan terbit tidak pernah diam-diam menelan lapang yang belum
/// punya angka.
@MainActor
struct ReviewViewModelTests {

    private final class SpyStore: SessionStoreProtocol, @unchecked Sendable {
        var savedCount = 0
        var saveError: Error?
        func allSessions() async throws -> [ExamSession] { [] }
        func save(_ snapshot: SessionSnapshot) async throws {
            if let saveError { throw saveError }
            savedCount += 1
        }
        func delete(_ session: ExamSession) async throws {}
        func writeFieldImage(_ data: Data, fileName: String, for session: ExamSession) throws {}
        func fieldImageURL(fileName: String, for session: ExamSession) -> URL {
            FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        }
    }

    private final class SilentAnalysis: AnalysisServiceProtocol, @unchecked Sendable {
        func analyze(imageData: Data) async throws -> AnalysisResult {
            AnalysisResult(btaCount: 0, confidence: 0, grade: .negative, analyzedAt: Date())
        }
    }

    private func analysis(_ count: Int, failure: String? = nil) -> FieldAnalysis {
        FieldAnalysis(
            readings: [DetectorReading(detector: .yolo, btaCount: count,
                                       confidence: 0.8, elapsed: 0.5, failure: failure)],
            primary: .yolo
        )
    }

    private func makeSession(counts: [Int]) -> ExamSession {
        let session = ExamSession()
        for c in counts {
            let f = session.appendField(imageFileName: "f.jpg")
            session.setAnalysis(analysis(c), for: f.id)
        }
        return session
    }

    private func makeViewModel(_ session: ExamSession, store: SpyStore = SpyStore()) -> ReviewViewModel {
        ReviewViewModel(
            session: session,
            store: store,
            queue: FieldAnalysisQueue(analysisService: SilentAnalysis(), store: store)
        )
    }

    @Test("Lapang pertama terpilih saat review dibuka")
    func firstFieldSelectedInitially() {
        let vm = makeViewModel(makeSession(counts: [3, 5, 1]))
        #expect(vm.selectedIndex == 0)
        #expect(vm.selectedField?.index == 0)
    }

    @Test("Navigasi maju-mundur berhenti di ujung")
    func navigationClampsAtEnds() {
        let vm = makeViewModel(makeSession(counts: [1, 2, 3]))

        vm.selectPrevious()
        #expect(vm.selectedIndex == 0, "Tidak boleh lewat dari lapang pertama")

        vm.selectNext(); vm.selectNext(); vm.selectNext(); vm.selectNext()
        #expect(vm.selectedIndex == 2, "Tidak boleh lewat dari lapang terakhir")
    }

    @Test("Keypad menulis koreksi ke lapang terpilih")
    func keypadWritesCorrection() async {
        let store = SpyStore()
        let session = makeSession(counts: [9, 9])
        let vm = makeViewModel(session, store: store)

        vm.openKeypad()
        vm.appendDigit("1"); vm.appendDigit("2")
        vm.commitKeypad()

        #expect(session.fields[0].correctedCount == 12)
        #expect(session.totalBTA == 21, "12 + 9")
        #expect(!vm.isKeypadPresented)

        try? await Task.sleep(for: .milliseconds(20))
        #expect(store.savedCount == 1, "Koreksi harus benar-benar tersimpan, bukan cuma di memori")
    }

    @Test("Koreksi nol tersimpan sebagai nol, bukan diabaikan")
    func zeroCorrectionIsStored() async {
        let store = SpyStore()
        let session = makeSession(counts: [7])
        let vm = makeViewModel(session, store: store)

        vm.openKeypad()
        vm.appendDigit("0")
        vm.commitKeypad()

        #expect(session.fields[0].correctedCount == 0)
        #expect(session.totalBTA == 0)
        #expect(session.examinedFieldCount == 1, "Nol tetap lapang yang terbaca")

        try? await Task.sleep(for: .milliseconds(20))
        #expect(store.savedCount == 1, "Nol tetap koreksi yang harus tersimpan ke disk")
    }

    @Test("Keypad kosong yang dikonfirmasi tidak mengubah apa pun")
    func emptyKeypadIsNoop() {
        let session = makeSession(counts: [7])
        let vm = makeViewModel(session)

        vm.openKeypad()
        vm.commitKeypad()

        #expect(session.fields[0].correctedCount == nil)
        #expect(session.totalBTA == 7)
    }

    @Test("Hapus digit dan batal tidak menyentuh lapang")
    func deleteAndCancel() {
        let session = makeSession(counts: [7])
        let vm = makeViewModel(session)

        vm.openKeypad()
        vm.appendDigit("5"); vm.appendDigit("5")
        vm.deleteDigit()
        #expect(vm.keypadText == "5")

        vm.cancelKeypad()
        #expect(session.fields[0].correctedCount == nil)
        #expect(!vm.isKeypadPresented)
    }

    @Test("Koreksi bisa dikembalikan ke hitungan model")
    func correctionCanBeCleared() async {
        let store = SpyStore()
        let session = makeSession(counts: [7])
        let vm = makeViewModel(session, store: store)

        vm.openKeypad(); vm.appendDigit("2"); vm.commitKeypad()
        #expect(session.totalBTA == 2)

        vm.clearCorrection()
        #expect(session.fields[0].correctedCount == nil)
        #expect(session.totalBTA == 7, "Kembali ke angka model")

        try? await Task.sleep(for: .milliseconds(20))
        #expect(store.savedCount == 2, "Koreksi maupun pembatalannya sama-sama harus tersimpan")
    }

    @Test("Membuang lapang mengubah total dan penyebut sekaligus")
    func excludingChangesBothSides() async {
        let store = SpyStore()
        let session = makeSession(counts: [4, 4, 4])
        let vm = makeViewModel(session, store: store)

        vm.toggleExcludedOnSelected()

        #expect(session.totalBTA == 8)
        #expect(session.examinedFieldCount == 2)

        vm.toggleExcludedOnSelected()
        #expect(session.examinedFieldCount == 3, "Bisa dikembalikan")

        try? await Task.sleep(for: .milliseconds(20))
        #expect(store.savedCount == 2, "Membuang maupun mengembalikan lapang sama-sama harus tersimpan")
    }

    @Test("Grade yang dipilih tersimpan di sesi")
    func gradeIsRecorded() {
        let session = makeSession(counts: [1])
        let vm = makeViewModel(session)

        vm.chooseGrade(.plus2)

        #expect(session.chosenGrade == .plus2)
        #expect(session.reportedGrade == .plus2)
    }

    @Test("Lapang gagal terdaftar sebagai belum selesai")
    func unresolvedFieldsAreListed() {
        let session = ExamSession()
        let ok = session.appendField(imageFileName: "f.jpg")
        session.setAnalysis(analysis(3), for: ok.id)
        let broken = session.appendField(imageFileName: "f.jpg")
        session.setAnalysis(analysis(0, failure: "ORT gagal"), for: broken.id)
        _ = session.appendField(imageFileName: "f.jpg")   // masih diantre

        let vm = makeViewModel(session)

        #expect(vm.unresolvedFields.count == 2,
                "Yang gagal maupun yang belum dianalisis sama-sama belum punya angka")
    }

    @Test("Terbit mengubah status dan menyimpan sesi")
    func publishSavesAndMarksPublished() async {
        let store = SpyStore()
        let session = makeSession(counts: [2, 2])
        let vm = makeViewModel(session, store: store)

        await vm.publish()

        #expect(session.status == .published)
        #expect(vm.isPublished)
        #expect(store.savedCount == 1)
        #expect(vm.errorMessage == nil)
    }

    @Test("Terbit yang gagal disimpan tidak berpura-pura berhasil")
    func failedPublishIsReported() async {
        let store = SpyStore()
        store.saveError = CocoaError(.fileWriteOutOfSpace)
        let session = makeSession(counts: [2])
        let vm = makeViewModel(session, store: store)

        await vm.publish()

        #expect(!vm.isPublished, "Hasil yang tidak tersimpan tidak boleh tampak terbit")
        #expect(vm.errorMessage != nil)
        #expect(session.status != .published)
    }

    @Test("Pesan galat hilang begitu penyimpanan berikutnya berhasil")
    func errorMessageClearsAfterSuccessfulSave() async {
        let store = SpyStore()
        store.saveError = CocoaError(.fileWriteOutOfSpace)
        let session = makeSession(counts: [7])
        let vm = makeViewModel(session, store: store)

        vm.openKeypad(); vm.appendDigit("3"); vm.commitKeypad()
        try? await Task.sleep(for: .milliseconds(20))
        #expect(vm.errorMessage != nil, "Penyimpanan yang gagal harus terlihat")

        store.saveError = nil
        vm.openKeypad(); vm.appendDigit("4"); vm.commitKeypad()
        try? await Task.sleep(for: .milliseconds(20))
        #expect(vm.errorMessage == nil,
                "Pesan galat lama tidak boleh bertahan setelah koreksi berikutnya tersimpan")
    }
}
