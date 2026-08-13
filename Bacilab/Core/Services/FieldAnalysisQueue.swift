import Foundation
import Observation

private let queueLog = Diag("antrean")

/// Menjalankan model atas lapang yang sudah tersimpan, di latar, sementara scan terus berjalan.
///
/// Scan mengambil frame tiap ~1,5 detik sedangkan satu lapang butuh beberapa detik di perangkat.
/// Kalau scan menunggu model, laju itu mustahil. Karena itu lapang ditulis ke disk lebih dulu
/// dan analisisnya menyusul — saat teknisi menekan Selesai, sebagian besar sudah rampung.
///
/// **Serial dengan sengaja.** Menjalankan beberapa lapang sekaligus menggilas CPU dan memicu
/// throttling termal di tengah sesi. Satu pekerja, satu lapang pada satu waktu.
///
/// Di-`@MainActor` karena ia memutasi `ExamSession` yang `@Observable` dan menggerakkan UI.
/// Kerja beratnya tetap di luar: `MultiDetectorService` menjalankan ORT di antrean privatnya.
@MainActor
@Observable
final class FieldAnalysisQueue {

    private struct Job {
        let fieldID: UUID
        let imageData: Data
    }

    private let analysisService: any AnalysisServiceProtocol
    private var jobs: [Job] = []
    private var worker: Task<Void, Never>?

    /// Berapa lapang masih menunggu, untuk ditampilkan sebagai "menganalisis n dari m".
    private(set) var remaining = 0

    init(analysisService: any AnalysisServiceProtocol) {
        self.analysisService = analysisService
    }

    func enqueue(fieldID: UUID, imageData: Data, into session: ExamSession) {
        jobs.append(Job(fieldID: fieldID, imageData: imageData))
        remaining = jobs.count
        startWorkerIfNeeded(session: session)
    }

    /// Menunggu antrean habis. Dipakai Review sebelum menampilkan angka final, dan oleh test.
    func waitUntilIdle() async {
        await worker?.value
    }

    func cancelAll() {
        worker?.cancel()
        jobs.removeAll()
        remaining = 0
    }

    // MARK: - Pekerja

    private func startWorkerIfNeeded(session: ExamSession) {
        guard worker == nil else { return }

        worker = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, let job = self.takeNextJob() {
                let analysis = await self.analyse(job)
                session.setAnalysis(analysis, for: job.fieldID)
                self.remaining = self.jobs.count
            }
            self.remaining = self.jobs.isEmpty ? 0 : self.jobs.count
            self.worker = nil
        }
    }

    private func takeNextJob() -> Job? {
        jobs.isEmpty ? nil : jobs.removeFirst()
    }

    private func analyse(_ job: Job) async -> FieldAnalysis {
        do {
            let result = try await analysisService.analyze(imageData: job.imageData, using: .all)
            return FieldAnalysis(readings: result.readings, primary: .resnet)
        } catch {
            queueLog.error("Analisis lapang gagal: \(error.localizedDescription)")
            // Kegagalan disimpan sebagai bacaan bertanda `failure`, bukan sebagai hitungan 0.
            // Nol berarti "model melihat lapang bersih"; keduanya tidak boleh tertukar.
            return FieldAnalysis(
                readings: [DetectorReading(
                    detector: .resnet,
                    btaCount: 0,
                    confidence: 0,
                    elapsed: 0,
                    failure: error.localizedDescription
                )],
                primary: .resnet
            )
        }
    }
}
