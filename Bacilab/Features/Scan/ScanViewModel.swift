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

        // One batch beyond wherever the session already stands — `batchTarget` is how much one
        // press adds, never how many fields a slide may have.
        //
        // A fixed ceiling at 20 made every grade except 3+ permanently unconfirmable: 2+ needs
        // 50 fields and 1+/Scanty/Negative need 100, so the app could never reach the thresholds
        // it grades against. Worse, it failed silently — at 20 fields the loop body simply never
        // ran, the shutter blinked, and Review's "Continue Scanning" button returned the analyst
        // to exactly that dead screen.
        let target = session.fields.count + ExamSession.batchTarget

        scanTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, session.fields.count < target {
                await self.captureField(session: session)
                guard !Task.isCancelled else { break }
                try? await Task.sleep(for: .milliseconds(self.scanIntervalMilliseconds))
            }
            self.isScanning = false
        }
    }

    // MARK: - Satu lapang

    /// Merekam satu lapang: potret → potong → tulis → catat → antre → simpan.
    ///
    /// Urutannya penting. Lapang baru dicatat ke sesi **setelah** berkasnya tertulis, supaya
    /// disk yang penuh tidak meninggalkan lapang yang gambarnya tidak ada. Dan lapang selalu
    /// dicatat kalau berkasnya tersimpan — ada BTA maupun tidak. Auto-scan lama hanya menambah
    /// ketika modelnya menemukan sesuatu, sehingga lapang kosong tidak pernah masuk penyebut
    /// dan grade Negatif secara struktural tidak bisa dicapai.
    ///
    /// `queue.enqueue` terjadi **sebelum** `store.save`, dengan sengaja. Kalau `save` gagal —
    /// disk penuh di tengah sesi, misalnya — lapangnya sudah tercatat (gambarnya sudah aman di
    /// disk) dan errornya tetap dilaporkan, tapi tanpa urutan ini lapang itu akan tertahan
    /// `pending` selamanya: tidak ada jalan lain untuk mengantrekannya lagi, padahal gambarnya
    /// sudah ada dan modelnya menganggur. `enqueue` sendiri tidak pernah throw, jadi
    /// menempatkannya sebelum `save` tidak mengubah kapan lapang dicatat atau kapan error
    /// muncul — hanya memastikan analisis tidak ikut gagal gara-gara penyimpanan sesi gagal.
    func captureField(session: ExamSession) async {
        do {
            let raw = try await cameraService.captureImage()
            guard !raw.isEmpty else { throw CameraError.captureFailed }
            try await record(raw, source: .camera, into: session)
        } catch {
            report(error)
        }
    }

    /// Records one field from a photo the analyst picked out of the library.
    ///
    /// Goes through exactly the same `record` path as a camera capture — same framing, same
    /// write-then-append order, same queue. Duplicating the pipeline here would make any
    /// difference between an imported field and a captured one part framing and part source,
    /// with no way to tell which.
    ///
    /// The field is tagged `.gallery` so a session mixing eyepiece and imported images says so
    /// rather than presenting one pooled count as a single acquisition.
    func importField(from raw: Data, into session: ExamSession) async {
        do {
            guard !raw.isEmpty else { throw CameraError.captureFailed }
            try await record(raw, source: .gallery, into: session)
        } catch {
            report(error)
        }
    }

    /// The one path a field is ever recorded by: frame → write → append → enqueue → save.
    ///
    /// Ordering is load-bearing. The field is appended only **after** its image is on disk, so a
    /// full disk cannot leave a field whose picture does not exist. And it is appended whatever
    /// the models later find — auto-scan used to increment only when the detector saw something,
    /// so empty fields never entered the denominator and grade Negatif was structurally
    /// unreachable.
    ///
    /// `queue.enqueue` sits **before** `store.save` deliberately: `enqueue` never throws, so its
    /// position changes neither when the field is recorded nor when an error surfaces, but a
    /// failing `save` would otherwise strand the field `pending` forever with its image already
    /// on disk and the models idle.
    private func record(_ raw: Data, source: FieldSource, into session: ExamSession) async throws {
        guard let image = UIImage(data: raw),
              let jpeg = FieldFraming.analysisJPEG(of: image)
        else { throw CameraError.captureFailed }

        // Only the live camera gets a focus verdict. An imported photo's sharpness is already
        // fixed, and flagging it "out of focus" would read as advice about an eyepiece the
        // analyst is not looking through.
        if source == .camera { updateFocus(from: jpeg) }

        let fileName = String(format: "field-%03d.jpg", session.fields.count)
        try store.writeFieldImage(jpeg, fileName: fileName, for: session)

        let field = session.appendField(imageFileName: fileName, source: source)
        queue.enqueue(fieldID: field.id, imageData: jpeg, into: session)
        try await store.save(session.snapshot())

        scanLog.note("field \(field.index) recorded from \(source.rawValue), \(jpeg.count) bytes")
    }

    private func report(_ error: Error) {
        errorMessage = error.localizedDescription
        scanLog.error("Recording a field failed: \(error.localizedDescription)")
    }

    private func updateFocus(from jpeg: Data) {
        guard let image = UIImage(data: jpeg) else { return }
        lastSharpness = FocusMetric.sharpness(of: image)
        isBlurry = FocusMetric.isBlurry(lastSharpness)
    }
}
