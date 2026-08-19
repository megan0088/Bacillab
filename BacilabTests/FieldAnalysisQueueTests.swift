import Testing
import Foundation
@testable import Bacilab

/// Antrean adalah satu-satunya jalan hasil model masuk ke sesi. Yang diuji: semua lapang
/// terlayani, satu per satu, dan kegagalan satu lapang tidak menjatuhkan sisanya.
@MainActor
struct FieldAnalysisQueueTests {

    /// Mencatat berapa banyak analisis berjalan bersamaan, supaya sifat serial bisa dibuktikan
    /// dan bukan sekadar diasumsikan.
    private final class StubAnalysisService: AnalysisServiceProtocol, @unchecked Sendable {
        private let lock = NSLock()
        private var active = 0
        private(set) var maxConcurrent = 0
        private(set) var callCount = 0

        var countPerField = 4
        var failEveryCall = false

        func analyze(imageData: Data) async throws -> AnalysisResult {
            lock.lock()
            active += 1
            maxConcurrent = max(maxConcurrent, active)
            callCount += 1
            let shouldFail = failEveryCall
            lock.unlock()

            try? await Task.sleep(for: .milliseconds(10))

            lock.lock()
            active -= 1
            lock.unlock()

            if shouldFail { throw AnalysisError.modelUnavailable }

            return AnalysisResult(
                btaCount: countPerField,
                confidence: 0.8,
                grade: .scanty,
                analyzedAt: Date(),
                detectedBoxes: [],
                readings: [DetectorReading(detector: .yolo11, btaCount: countPerField,
                                           confidence: 0.8, elapsed: 0.01)]
            )
        }
    }

    /// Mencatat tiap sesi yang disimpan, supaya test bisa memeriksa bahwa hasil analisis
    /// sungguh sampai ke disk — bukan hanya bertahan di `ExamSession` yang ada di memori.
    private final class SpyStore: SessionStoreProtocol, @unchecked Sendable {
        private let lock = NSLock()
        private var _savedSnapshots: [SessionSnapshot] = []

        var savedSnapshots: [SessionSnapshot] {
            lock.lock(); defer { lock.unlock() }
            return _savedSnapshots
        }

        func allSessions() async throws -> [ExamSession] { [] }
        func save(_ snapshot: SessionSnapshot) async throws {
            lock.lock()
            _savedSnapshots.append(snapshot)
            lock.unlock()
        }
        func delete(_ session: ExamSession) async throws {}
        func writeFieldImage(_ data: Data, fileName: String, for session: ExamSession) throws {}
        func fieldImageURL(fileName: String, for session: ExamSession) -> URL {
            FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        }
    }

    @Test("Semua lapang yang diantre akhirnya teranalisis")
    func allQueuedFieldsGetAnalysed() async {
        let service = StubAnalysisService()
        let queue = FieldAnalysisQueue(analysisService: service, store: SpyStore())
        let session = ExamSession()

        for _ in 0..<5 {
            let field = session.appendField(imageFileName: "f.jpg")
            queue.enqueue(fieldID: field.id, imageData: Data([0x01]), into: session)
        }

        await queue.waitUntilIdle()

        #expect(service.callCount == 5)
        #expect(session.pendingAnalysisCount == 0)
        #expect(session.examinedFieldCount == 5)
        #expect(session.totalBTA == 20)
        #expect(queue.remaining == 0)
    }

    @Test("Analisis berjalan satu per satu, bukan bersamaan")
    func analysisRunsSerially() async {
        let service = StubAnalysisService()
        let queue = FieldAnalysisQueue(analysisService: service, store: SpyStore())
        let session = ExamSession()

        for _ in 0..<6 {
            let field = session.appendField(imageFileName: "f.jpg")
            queue.enqueue(fieldID: field.id, imageData: Data([0x01]), into: session)
        }

        await queue.waitUntilIdle()

        #expect(service.maxConcurrent == 1,
                "Beberapa lapang berjalan bersamaan — CPU akan tergilas dan telepon memanas")
    }

    @Test("Model yang gagal menjadi lapang perlu-hitung-manual, bukan nol")
    func failureBecomesManualCountField() async {
        let service = StubAnalysisService()
        service.failEveryCall = true
        let queue = FieldAnalysisQueue(analysisService: service, store: SpyStore())
        let session = ExamSession()

        let field = session.appendField(imageFileName: "f.jpg")
        queue.enqueue(fieldID: field.id, imageData: Data([0x01]), into: session)
        await queue.waitUntilIdle()

        let stored = session.field(withID: field.id)
        #expect(stored?.analysis != nil, "Lapang harus punya hasil, meski hasilnya kegagalan")
        #expect(stored?.effectiveCount == nil, "Kegagalan tidak boleh terbaca sebagai 0 BTA")
        #expect(session.examinedFieldCount == 0)
        #expect(session.fieldsNeedingManualCount.count == 1)
    }

    @Test("Satu lapang gagal tidak menghentikan sisanya")
    func oneFailureDoesNotStopTheQueue() async {
        let service = StubAnalysisService()
        let queue = FieldAnalysisQueue(analysisService: service, store: SpyStore())
        let session = ExamSession()

        let first = session.appendField(imageFileName: "f.jpg")
        service.failEveryCall = true
        queue.enqueue(fieldID: first.id, imageData: Data([0x01]), into: session)
        await queue.waitUntilIdle()

        service.failEveryCall = false
        for _ in 0..<3 {
            let field = session.appendField(imageFileName: "f.jpg")
            queue.enqueue(fieldID: field.id, imageData: Data([0x01]), into: session)
        }
        await queue.waitUntilIdle()

        #expect(session.examinedFieldCount == 3)
        #expect(session.fieldsNeedingManualCount.count == 1)
    }

    @Test("Sisa antrean turun sampai nol")
    func remainingDropsToZero() async {
        let service = StubAnalysisService()
        let queue = FieldAnalysisQueue(analysisService: service, store: SpyStore())
        let session = ExamSession()

        for _ in 0..<3 {
            let field = session.appendField(imageFileName: "f.jpg")
            queue.enqueue(fieldID: field.id, imageData: Data([0x01]), into: session)
        }
        #expect(queue.remaining > 0)

        await queue.waitUntilIdle()
        #expect(queue.remaining == 0)
    }

    @Test("Membatalkan antrean menghentikan pekerjaan yang belum jalan")
    func cancelStopsPendingWork() async {
        let service = StubAnalysisService()
        let queue = FieldAnalysisQueue(analysisService: service, store: SpyStore())
        let session = ExamSession()

        for _ in 0..<10 {
            let field = session.appendField(imageFileName: "f.jpg")
            queue.enqueue(fieldID: field.id, imageData: Data([0x01]), into: session)
        }

        // `enqueue` tidak pernah `await`, jadi tanpa jeda ini seluruh loop plus `cancelAll()`
        // berjalan sebagai satu blok sinkron sebelum pekerja sempat mengeksekusi satu baris
        // pun — `callCount` akan 0 apa pun implementasinya, termasuk yang tidak pernah
        // mengecek `Task.isCancelled` sama sekali. Jeda ini memastikan pekerja benar-benar
        // mengambil dan memulai lapang pertama sebelum dibatalkan.
        try? await Task.sleep(for: .milliseconds(5))

        queue.cancelAll()
        await queue.waitUntilIdle()

        #expect(queue.remaining == 0)
        #expect(service.callCount == 1,
                "Lapang pertama yang sudah telanjur jalan boleh selesai, tapi sisanya harus berhenti")
    }

    @Test("Lapang yang diantre setelah cancelAll() tetap diproses pekerja baru")
    func enqueueAfterCancelStartsFreshWorker() async {
        let service = StubAnalysisService()
        let queue = FieldAnalysisQueue(analysisService: service, store: SpyStore())
        let session = ExamSession()

        let first = session.appendField(imageFileName: "f.jpg")
        queue.enqueue(fieldID: first.id, imageData: Data([0x01]), into: session)

        // Biarkan pekerja benar-benar mulai menganalisis `first` sebelum dibatalkan, supaya
        // `cancelAll()` betul-betul balapan dengan pekerja yang sedang di tengah `analyse`,
        // bukan dengan pekerja yang belum sempat jalan sama sekali.
        try? await Task.sleep(for: .milliseconds(5))

        queue.cancelAll()

        let second = session.appendField(imageFileName: "f.jpg")
        queue.enqueue(fieldID: second.id, imageData: Data([0x01]), into: session)

        await queue.waitUntilIdle()

        #expect(session.field(withID: second.id)?.analysis != nil,
                "Lapang yang diantre setelah cancelAll() harus tetap dianalisis oleh pekerja baru")
        #expect(queue.remaining == 0)
    }

    @Test("Sesi tersimpan ke disk setelah satu lapang selesai dianalisis")
    func sessionIsPersistedAfterFieldAnalysis() async throws {
        let service = StubAnalysisService()
        service.countPerField = 6
        let store = SpyStore()
        let queue = FieldAnalysisQueue(analysisService: service, store: store)
        let session = ExamSession()

        let field = session.appendField(imageFileName: "f.jpg")
        queue.enqueue(fieldID: field.id, imageData: Data([0x01]), into: session)

        await queue.waitUntilIdle()
        // `persist` di dalam antrean sengaja fire-and-forget (lihat dokumentasinya) — pekerja
        // tidak menunggunya, jadi `waitUntilIdle()` saja tidak menjamin tulisan ini sudah
        // selesai. Jeda singkat ini memakai pola yang sama dengan autosave Review di
        // `ReviewViewModelTests` untuk kasus fire-and-forget yang serupa.
        try? await Task.sleep(for: .milliseconds(20))

        #expect(!store.savedSnapshots.isEmpty,
                "Sesi harus tersimpan setelah lapang selesai dianalisis, bukan cuma tinggal di memori")

        // Diperiksa lewat snapshot, bukan lewat objek sesi. Sebelumnya spy menyimpan referensi
        // `ExamSession`, jadi asersi ini membaca objek yang masih hidup — ia akan lulus bahkan
        // seandainya `save` tidak menulis apa pun. Snapshot adalah salinan pada saat penyimpanan,
        // jadi sekarang ia benar-benar membuktikan apa yang dikirim ke penyimpanan.
        let saved = try #require(store.savedSnapshots.last)
        let savedField = try #require(saved.fields.first { $0.id == field.id })
        #expect(savedField.analysis != nil, "Simpanan harus membawa hasil analisis lapang ini")
        #expect(savedField.effectiveCount == 6)
    }
}
