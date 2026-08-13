import Testing
import Foundation
import UIKit
import AVFoundation
@testable import Bacilab

/// Covers the wiring the detector depends on: a capture has to produce real image
/// bytes, those bytes have to reach `ResNetAnalysisService`, and the count it returns
/// has to land on the shared draft. Before photo capture was implemented this whole
/// path silently no-opped — `captureImage()` returned empty data, so `analyze` was
/// never called and every slide came back as 0 BTA.
struct CaptureFlowTests {

    private func makeViewModel(_ deps: AppDependencies) -> CaptureViewModel {
        CaptureViewModel(
            cameraService: deps.cameraService,
            analysisService: deps.analysisService,
            sampleRepository: deps.sampleRepository
        )
    }

    /// Stands in for a device-side capture failure — autofocus giving up, the connection
    /// dropping — which the simulator's always-succeeding camera can never produce.
    private final class FailingCameraService: CameraServiceProtocol {
        var isRunning = true
        let session = AVCaptureSession()
        func startSession() async throws {}
        func stopSession() {}
        func captureImage() async throws -> Data { throw CameraError.captureFailed }
    }

    private final class DeniedCameraService: CameraServiceProtocol {
        var isRunning = false
        let session = AVCaptureSession()
        func startSession() async throws { throw CameraError.permissionDenied }
        func stopSession() {}
        func captureImage() async throws -> Data { throw CameraError.permissionDenied }
    }

    @Test("Izin ditolak memunculkan jalur ke Pengaturan, bukan error biasa")
    func deniedPermissionIsDistinguished() async throws {
        let deps = AppDependencies()
        let viewModel = CaptureViewModel(
            cameraService: DeniedCameraService(),
            analysisService: deps.analysisService,
            sampleRepository: deps.sampleRepository
        )

        await viewModel.startCamera()

        #expect(viewModel.permissionDenied,
                "Izin ditolak harus dibedakan agar analis bisa diarahkan ke Pengaturan")
        #expect(viewModel.errorMessage == nil,
                "Jangan tampilkan alert error generik untuk kasus izin")
    }

    @Test("Kamera menghasilkan gambar yang bisa dibaca")
    func captureProducesDecodableImage() async throws {
        let data = try await CameraService().captureImage()

        #expect(!data.isEmpty, "captureImage() mengembalikan data kosong")
        let image = try #require(UIImage(data: data), "Data bukan gambar yang valid")
        #expect(image.size.width == 1024 && image.size.height == 1024)
    }

    @Test("Satu capture menjalankan deteksi dan menambah hitungan BTA")
    func captureRunsDetectionAndAccumulates() async throws {
        let deps = AppDependencies()
        let viewModel = makeViewModel(deps)
        let draft = SampleDraft()

        await viewModel.capture(into: draft)

        #expect(viewModel.errorMessage == nil,
                "Capture gagal: \(viewModel.errorMessage ?? "")")
        #expect(draft.capturedFieldCount == 1)
        #expect(draft.imageData?.isEmpty == false, "Gambar hasil capture tidak tersimpan di draft")
        #expect(draft.manualBTACount > 0,
                "Model tidak menghasilkan deteksi — jalur kamera→analisis putus")
        // Must be the detector's own figure, never a placeholder or invented value
        #expect(draft.aiConfidence > 0.25 && draft.aiConfidence <= 1.0,
                "aiConfidence = \(draft.aiConfidence), bukan confidence nyata dari model")
    }

    @Test("Grade pilihan analis tidak ditimpa oleh capture berikutnya")
    func manualGradeSurvivesFurtherCaptures() async throws {
        let deps = AppDependencies()
        let viewModel = makeViewModel(deps)
        let draft = SampleDraft()

        await viewModel.capture(into: draft)
        let auto = draft.grade
        draft.selectGrade(.scanty)
        await viewModel.capture(into: draft)

        #expect(draft.grade == .scanty,
                "Pilihan analis berubah jadi \(draft.grade.rawValue) setelah capture")
        // `.negative` is what a detector that never ran would produce, and it also satisfies
        // "berbeda dari .scanty" — so require a grade that only real detections can give.
        #expect(auto != .scanty && auto != .negative,
                "Prasyarat test: grade otomatis harus berasal dari deteksi nyata, dapat \(auto.rawValue)")
        // The count itself must keep accumulating — only the grade is pinned
        #expect(draft.capturedFieldCount == 2)
    }

    @Test("Capture yang gagal tidak menambah jumlah field")
    func failedCaptureDoesNotCountAsField() async throws {
        let deps = AppDependencies()
        let viewModel = CaptureViewModel(
            cameraService: FailingCameraService(),
            analysisService: deps.analysisService,
            sampleRepository: deps.sampleRepository
        )
        let draft = SampleDraft()

        await viewModel.capture(into: draft)

        #expect(draft.capturedFieldCount == 0,
                "Field bertambah padahal tidak ada gambar yang dianalisis")
        #expect(draft.manualBTACount == 0)
        #expect(viewModel.errorMessage != nil, "Kegagalan harus dilaporkan ke analis")
    }

    @Test("Capture kedua menambah, bukan menimpa, hitungan sebelumnya")
    func secondCaptureAccumulates() async throws {
        let deps = AppDependencies()
        let viewModel = makeViewModel(deps)
        let draft = SampleDraft()

        await viewModel.capture(into: draft)
        let afterFirst = draft.manualBTACount
        await viewModel.capture(into: draft)

        // 0 == 0 * 2 holds, so without this the accumulation check passes even when the
        // detector produced nothing at all.
        #expect(afterFirst > 0, "Capture pertama tidak menghasilkan deteksi apa pun")
        #expect(draft.capturedFieldCount == 2)
        #expect(draft.manualBTACount == afterFirst * 2,
                "Lapang pandang sintetis identik, jadi hitungannya harus persis berlipat")
        // Same density over two fields — the extrapolated grade must not drift
        #expect(draft.grade == BTAGrade.grade(for: afterFirst, across: 1))
    }
}
