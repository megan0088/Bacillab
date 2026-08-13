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
                readings: [DetectorReading(detector: .resnet, btaCount: countPerField,
                                           confidence: 0.8, elapsed: 0.01)]
            )
        }
    }

    @Test("Semua lapang yang diantre akhirnya teranalisis")
    func allQueuedFieldsGetAnalysed() async {
        let service = StubAnalysisService()
        let queue = FieldAnalysisQueue(analysisService: service)
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
        let queue = FieldAnalysisQueue(analysisService: service)
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
        let queue = FieldAnalysisQueue(analysisService: service)
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
        let queue = FieldAnalysisQueue(analysisService: service)
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
        let queue = FieldAnalysisQueue(analysisService: service)
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
        let queue = FieldAnalysisQueue(analysisService: service)
        let session = ExamSession()

        for _ in 0..<10 {
            let field = session.appendField(imageFileName: "f.jpg")
            queue.enqueue(fieldID: field.id, imageData: Data([0x01]), into: session)
        }

        queue.cancelAll()
        await queue.waitUntilIdle()

        #expect(queue.remaining == 0)
        #expect(service.callCount < 10, "Antrean yang dibatalkan tetap menghabiskan semua pekerjaan")
    }
}
