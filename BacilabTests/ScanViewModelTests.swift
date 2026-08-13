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
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScanViewModelTests-\(UUID().uuidString)")

        func allSessions() async throws -> [ExamSession] { [] }
        func save(_ session: ExamSession) async throws { savedCount += 1 }
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
                readings: [DetectorReading(detector: .resnet, btaCount: btaCount,
                                           confidence: 0.8, elapsed: 0.01)]
            )
        }
    }

    private func makeViewModel(
        camera: CameraServiceProtocol,
        store: SessionStoreProtocol,
        analysis: AnalysisServiceProtocol = SilentAnalysis()
    ) -> ScanViewModel {
        ScanViewModel(
            cameraService: camera,
            store: store,
            queue: FieldAnalysisQueue(analysisService: analysis)
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
}
