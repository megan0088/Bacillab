import AVFoundation
import Foundation
import Observation
import UIKit

private let scanLog = Diag("scan")

/// Menjalankan sesi scan. **Tidak tahu apa-apa tentang BTA.**
///
/// Tugasnya hanya menghasilkan lapang: memotret, memotong persegi, menulis ke disk,
/// mencatatnya ke sesi, lalu mengantrekan analisisnya. Hitungan, grade, dan perbandingan
/// model semuanya milik layar Review.
@MainActor
@Observable
final class ScanViewModel {

    private let cameraService: any CameraServiceProtocol
    private let store: any SessionStoreProtocol
    let queue: FieldAnalysisQueue

    var isScanning = false
    var errorMessage: String?
    var permissionDenied = false

    /// Ketajaman frame terakhir dan apakah ia dianggap buram. Peringatan saja — tidak pernah
    /// memblokir capture, karena ambangnya belum dikalibrasi terhadap preparat sungguhan.
    private(set) var lastSharpness: Double = 0
    private(set) var isBlurry = false

    /// Jeda antar lapang. Dapat diperkecil oleh test supaya loop tidak menunggu 1,5 detik.
    var scanIntervalMilliseconds = 1500

    private var scanTask: Task<Void, Never>?

    var session: AVCaptureSession { cameraService.session }

    init(
        cameraService: any CameraServiceProtocol,
        store: any SessionStoreProtocol,
        queue: FieldAnalysisQueue
    ) {
        self.cameraService = cameraService
        self.store = store
        self.queue = queue
    }

    // MARK: - Kamera

    func startCamera() async {
        do {
            try await cameraService.startSession()
        } catch CameraError.permissionDenied {
            permissionDenied = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopCamera() {
        stopScan()
        cameraService.stopSession()
    }

    // MARK: - Loop scan

    func toggleScan(session: ExamSession) {
        if isScanning { stopScan() } else { startScan(session: session) }
    }

    func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    private func startScan(session: ExamSession) {
        guard !isScanning else { return }
        isScanning = true

        scanTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, session.fields.count < ExamSession.batchTarget {
                await self.captureField(session: session)
                guard !Task.isCancelled else { break }
                try? await Task.sleep(for: .milliseconds(self.scanIntervalMilliseconds))
            }
            self.isScanning = false
        }
    }

    // MARK: - Satu lapang

    /// Merekam satu lapang: potret → potong → tulis → catat → antre.
    ///
    /// Urutannya penting. Lapang baru dicatat ke sesi **setelah** berkasnya tertulis, supaya
    /// disk yang penuh tidak meninggalkan lapang yang gambarnya tidak ada. Dan lapang selalu
    /// dicatat kalau berkasnya tersimpan — ada BTA maupun tidak. Auto-scan lama hanya menambah
    /// ketika modelnya menemukan sesuatu, sehingga lapang kosong tidak pernah masuk penyebut
    /// dan grade Negatif secara struktural tidak bisa dicapai.
    func captureField(session: ExamSession) async {
        do {
            let raw = try await cameraService.captureImage()
            guard !raw.isEmpty else { throw CameraError.captureFailed }

            guard let image = UIImage(data: raw),
                  let jpeg = FieldFraming.analysisJPEG(of: image)
            else { throw CameraError.captureFailed }

            updateFocus(from: jpeg)

            let fileName = String(format: "field-%03d.jpg", session.fields.count)
            try store.writeFieldImage(jpeg, fileName: fileName, for: session)

            let field = session.appendField(imageFileName: fileName)
            try await store.save(session)
            queue.enqueue(fieldID: field.id, imageData: jpeg, into: session)

            scanLog.note("lapang \(field.index) direkam, \(jpeg.count) bita")
        } catch {
            errorMessage = error.localizedDescription
            scanLog.error("Rekam lapang gagal: \(error.localizedDescription)")
        }
    }

    private func updateFocus(from jpeg: Data) {
        guard let image = UIImage(data: jpeg) else { return }
        lastSharpness = FocusMetric.sharpness(of: image)
        isBlurry = FocusMetric.isBlurry(lastSharpness)
    }
}
