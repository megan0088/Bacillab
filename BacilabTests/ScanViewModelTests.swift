import Testing
import Foundation
import UIKit
import AVFoundation
@testable import Bacilab

/// Sesi scan buta terhadap BTA: ia hanya menghasilkan lapang. Yang diuji di sini adalah
/// penyebut grading — lapang mana yang bertambah dan mana yang tidak.
@MainActor
struct ScanViewModelTests {

    // MARK: - Stub

    private func jpegBytes(side: CGFloat = 1200) -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
            .image { ctx in
                UIColor.blue.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            }
        return image.jpegData(compressionQuality: 0.9)!
    }

    private final class StubCamera: CameraServiceProtocol, @unchecked Sendable {
        var isRunning = true
        let session = AVCaptureSession()
        var payload: Data
        var error: Error?
        var startError: Error?

        init(payload: Data) { self.payload = payload }

        func startSession() async throws { if let startError { throw startError } }
        func stopSession() {}
        func captureImage() async throws -> Data {
            if let error { throw error }
            return payload
        }
    }

    private final class SpyStore: SessionStoreProtocol, @unchecked Sendable {
        var savedCount = 0
        var writtenFiles: [String] = []
        var writeError: Error?
        var saveError: Error?
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScanViewModelTests-\(UUID().uuidString)")

        func allSessions() async throws -> [ExamSession] { [] }
        func save(_ snapshot: SessionSnapshot) async throws {
            if let saveError { throw saveError }
            savedCount += 1
        }
        func delete(_ session: ExamSession) async throws {}
        func writeFieldImage(_ data: Data, fileName: String, for session: ExamSession) throws {
            if let writeError { throw writeError }
            writtenFiles.append(fileName)
        }
        func fieldImageURL(fileName: String, for session: ExamSession) -> URL {
            root.appendingPathComponent(fileName)
        }
    }

    private final class SilentAnalysis: AnalysisServiceProtocol, @unchecked Sendable {
        var btaCount = 0
        func analyze(imageData: Data) async throws -> AnalysisResult {
            AnalysisResult(
                btaCount: btaCount, confidence: 0.8, grade: .negative, analyzedAt: Date(),
                detectedBoxes: [],
                readings: [DetectorReading(detector: .yolo, btaCount: btaCount,
                                           confidence: 0.8, elapsed: 0.01)]
            )
        }
    }

    private func makeViewModel(
        camera: CameraServiceProtocol,
        store: SessionStoreProtocol,
        analysis: AnalysisServiceProtocol = SilentAnalysis()
    ) -> ScanViewModel {
        // Antrean sengaja dapat `SpyStore` sendiri, terpisah dari `store` di atas: tulisannya
        // berjalan di latar dan tidak ditunggu (lihat `FieldAnalysisQueue.persist`), jadi kalau
        // ia berbagi `store` yang sama dengan ScanViewModel, `store.savedCount` di test yang
        // tidak memanggil `queue.waitUntilIdle()` (mis. `eachFieldIsPersisted`) bisa berubah
        // kapan saja pekerja antrean kebetulan selesai — persis kerapuhan yang mau dihindari.
        // Persistensi milik antrean sendiri diuji di `FieldAnalysisQueueTests`.
        ScanViewModel(
            cameraService: camera,
            store: store,
            queue: FieldAnalysisQueue(analysisService: analysis, store: SpyStore())
        )
    }

    // MARK: - Test

    @Test("Lapang tanpa BTA tetap terhitung")
    func emptyFieldStillCounts() async {
        let store = SpyStore()
        let analysis = SilentAnalysis()
        analysis.btaCount = 0
        let vm = makeViewModel(camera: StubCamera(payload: jpegBytes()), store: store,
                               analysis: analysis)
        let session = ExamSession()

        await vm.captureField(session: session)
        await vm.queue.waitUntilIdle()

        #expect(session.fields.count == 1)
        #expect(session.examinedFieldCount == 1,
                "Lapang kosong wajib masuk penyebut — inilah cacat yang membuat Negatif mustahil")
        #expect(session.totalBTA == 0)
        #expect(vm.errorMessage == nil)
    }

    @Test("Sepuluh lapang kosong menghasilkan sepuluh lapang, bukan nol")
    func tenEmptyFieldsCountAsTen() async {
        let store = SpyStore()
        let vm = makeViewModel(camera: StubCamera(payload: jpegBytes()), store: store)
        let session = ExamSession()

        for _ in 0..<10 { await vm.captureField(session: session) }
        await vm.queue.waitUntilIdle()

        #expect(session.examinedFieldCount == 10)
        #expect(session.suggestedGrade == .negative)
    }

    @Test("Capture yang gagal tidak menambah lapang")
    func failedCaptureAddsNothing() async {
        let store = SpyStore()
        let camera = StubCamera(payload: jpegBytes())
        camera.error = CameraError.captureFailed
        let vm = makeViewModel(camera: camera, store: store)
        let session = ExamSession()

        await vm.captureField(session: session)

        #expect(session.fields.isEmpty,
                "Lapang bertambah padahal tidak ada gambar — penyebut jadi menggelembung")
        #expect(store.writtenFiles.isEmpty)
        #expect(vm.errorMessage != nil, "Kegagalan harus dilaporkan ke analis")
    }

    @Test("Data kamera kosong diperlakukan sebagai kegagalan")
    func emptyDataIsAFailure() async {
        let store = SpyStore()
        let vm = makeViewModel(camera: StubCamera(payload: Data()), store: store)
        let session = ExamSession()

        await vm.captureField(session: session)

        #expect(session.fields.isEmpty)
        #expect(vm.errorMessage != nil)
    }

    @Test("Gagal menulis ke disk tidak meninggalkan lapang tanpa gambar")
    func diskFailureLeavesNoOrphanField() async {
        let store = SpyStore()
        store.writeError = CocoaError(.fileWriteOutOfSpace)
        let vm = makeViewModel(camera: StubCamera(payload: jpegBytes()), store: store)
        let session = ExamSession()

        await vm.captureField(session: session)

        #expect(session.fields.isEmpty,
                "Lapang hanya boleh dicatat setelah gambarnya benar-benar tersimpan")
        #expect(vm.errorMessage != nil)
    }

    @Test("Setiap lapang menulis berkas dan menyimpan sesi")
    func eachFieldIsPersisted() async {
        let store = SpyStore()
        let vm = makeViewModel(camera: StubCamera(payload: jpegBytes()), store: store)
        let session = ExamSession()

        await vm.captureField(session: session)
        await vm.captureField(session: session)

        #expect(store.writtenFiles == ["field-000.jpg", "field-001.jpg"])
        #expect(store.savedCount == 2, "Autosave tiap lapang — sesi 20 lapang tidak boleh hilang")
    }

    @Test("Izin ditolak dibedakan dari error biasa")
    func deniedPermissionIsDistinguished() async {
        let camera = StubCamera(payload: jpegBytes())
        camera.startError = CameraError.permissionDenied
        let vm = makeViewModel(camera: camera, store: SpyStore())

        await vm.startCamera()

        #expect(vm.permissionDenied)
        #expect(vm.errorMessage == nil, "Jangan tampilkan alert generik untuk kasus izin")
    }

    @Test("Lapang yang direkam diantrekan untuk dianalisis")
    func capturedFieldIsQueued() async {
        let store = SpyStore()
        let analysis = SilentAnalysis()
        analysis.btaCount = 7
        let vm = makeViewModel(camera: StubCamera(payload: jpegBytes()), store: store,
                               analysis: analysis)
        let session = ExamSession()

        await vm.captureField(session: session)
        await vm.queue.waitUntilIdle()

        #expect(session.totalBTA == 7, "Hasil antrean tidak sampai ke sesi")
    }

    @Test("Gagal menyimpan sesi tidak menghalangi lapang dianalisis")
    func saveFailureStillQueuesAnalysis() async {
        let store = SpyStore()
        store.saveError = CocoaError(.fileWriteOutOfSpace)
        let analysis = SilentAnalysis()
        analysis.btaCount = 5
        let vm = makeViewModel(camera: StubCamera(payload: jpegBytes()), store: store,
                               analysis: analysis)
        let session = ExamSession()

        await vm.captureField(session: session)

        #expect(session.fields.count == 1,
                "Gambarnya sudah tersimpan di disk — lapang tetap dicatat walau sesi gagal disimpan")
        #expect(vm.errorMessage != nil, "Kegagalan simpan sesi tetap harus dilaporkan")

        await vm.queue.waitUntilIdle()

        #expect(session.totalBTA == 5,
                "Lapang tidak boleh tertahan pending selamanya hanya karena sesi gagal disimpan")
    }

    @Test("Auto-scan berhenti tepat di batchTarget")
    func autoScanStopsAtBatchTarget() async {
        let store = SpyStore()
        let vm = makeViewModel(camera: StubCamera(payload: jpegBytes()), store: store)
        vm.scanIntervalMilliseconds = 1
        let session = ExamSession()

        vm.toggleScan(session: session)

        var waited = 0
        while vm.isScanning, waited < 5000 {
            try? await Task.sleep(for: .milliseconds(25))
            waited += 25
        }

        #expect(session.fields.count == ExamSession.batchTarget,
                "Loop harus berhenti tepat di batchTarget, bukan lebih atau kurang")
        #expect(vm.isScanning == false)
    }

    /// `batchTarget` adalah seberapa banyak satu tekan menambah, bukan plafon sesi.
    ///
    /// Sebelumnya kondisi loop membandingkan langsung ke `batchTarget`, jadi begitu sesi punya
    /// 20 lapang tombol scan tidak melakukan apa pun — diam, tanpa pesan. Akibatnya 2+ (50
    /// lapang) dan 1+/Scanty/Negatif (100 lapang) **tidak akan pernah bisa final**, dan tombol
    /// "Continue Scanning" di Review mengembalikan analis ke layar mati itu.
    @Test("Tekan kedua menambah satu batch lagi, bukan berhenti di plafon")
    func secondPressAddsAnotherBatch() async {
        let store = SpyStore()
        let vm = makeViewModel(camera: StubCamera(payload: jpegBytes()), store: store)
        vm.scanIntervalMilliseconds = 1
        let session = ExamSession()

        func scanOneBatch() async {
            vm.toggleScan(session: session)
            var waited = 0
            while vm.isScanning, waited < 5000 {
                try? await Task.sleep(for: .milliseconds(25))
                waited += 25
            }
        }

        await scanOneBatch()
        #expect(session.fields.count == ExamSession.batchTarget)

        await scanOneBatch()

        #expect(session.fields.count == ExamSession.batchTarget * 2,
                "Tekan kedua harus menambah satu batch penuh; kalau tetap 20, gerbang WHO untuk 2+, 1+, Scanty dan Negatif tidak akan pernah bisa dipenuhi")
        #expect(vm.isScanning == false)
    }

    @Test("stopScan menghentikan loop sebelum batchTarget dan membersihkan isScanning")
    func stopScanEndsLoopMidFlight() async {
        let store = SpyStore()
        let vm = makeViewModel(camera: StubCamera(payload: jpegBytes()), store: store)
        vm.scanIntervalMilliseconds = 50
        let session = ExamSession()

        vm.toggleScan(session: session)
        #expect(vm.isScanning)

        try? await Task.sleep(for: .milliseconds(120))
        vm.stopScan()

        #expect(vm.isScanning == false)

        // Beri jeda singkat untuk capture yang mungkin masih berjalan saat stopScan dipanggil.
        try? await Task.sleep(for: .milliseconds(50))
        let countAfterStop = session.fields.count
        #expect(countAfterStop > 0)
        #expect(countAfterStop < ExamSession.batchTarget,
                "Kalau sudah mencapai batchTarget, test ini tidak menguji apa-apa")

        // Tidak boleh ada lapang baru bertambah setelah dihentikan.
        try? await Task.sleep(for: .milliseconds(300))
        #expect(session.fields.count == countAfterStop,
                "stopScan harus benar-benar menghentikan loop, bukan cuma menunda")
    }
}
