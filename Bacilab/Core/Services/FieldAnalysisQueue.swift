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
///
/// **Menyimpan sesi setelah tiap lapang selesai dianalisis, bukan hanya menyimpannya di
/// memori.** `ScanViewModel.captureField` menyimpan sebelum analisis selesai, dan Review baru
/// menyimpan lagi saat analis mengoreksi sesuatu — di antara keduanya, hasil model yang sudah
/// jadi hanya ada di `ExamSession` yang `@Observable`. Kalau app dibunuh persis di jendela itu,
/// lapang yang sudah selesai dianalisis kembali dengan `analysis: nil` saat sesi dibuka lagi,
/// dan tidak ada apa pun yang mengantrekannya ulang — lapang itu tertahan `pending` selamanya.
@MainActor
@Observable
final class FieldAnalysisQueue {

    private struct Job {
        let fieldID: UUID
        let imageData: Data
        /// Sesi milik lapang ini — bukan "sesi yang kebetulan aktif saat pekerja pertama kali
        /// dimulai". Tiap `enqueue` membawa sesinya sendiri, dan hasilnya harus kembali ke
        /// sesi yang sama persis, bahkan kalau pekerja yang memprosesnya awalnya dimulai oleh
        /// `enqueue` lain untuk sesi lain.
        let session: ExamSession
    }

    private let analysisService: any AnalysisServiceProtocol
    private let store: any SessionStoreProtocol
    private var jobs: [Job] = []
    private var worker: Task<Void, Never>?

    /// Naik satu setiap `cancelAll()`. Pekerja yang sudah berjalan sebelum kenaikan ini adalah
    /// pekerja basi: kalau ia sedang di tengah `analyse` saat dibatalkan, ia dibiarkan
    /// menyelesaikan lapang yang sudah telanjur diambilnya, tapi begitu itu selesai ia
    /// mencocokkan generasinya sebelum menyentuh `worker`/`remaining` lagi. Tanpa ini, pekerja
    /// basi yang bangun belakangan bisa menimpa `worker`/`remaining` milik pekerja baru yang
    /// sudah mulai memproses antrean berikutnya — persis kecelakaan yang mau dicegah.
    private var generation = 0

    /// Berapa lapang masih menunggu, untuk ditampilkan sebagai "menganalisis n dari m".
    private(set) var remaining = 0

    init(analysisService: any AnalysisServiceProtocol, store: any SessionStoreProtocol) {
        self.analysisService = analysisService
        self.store = store
    }

    func enqueue(fieldID: UUID, imageData: Data, into session: ExamSession) {
        jobs.append(Job(fieldID: fieldID, imageData: imageData, session: session))
        remaining = jobs.count
        startWorkerIfNeeded()
    }

    /// Menunggu antrean habis. Dipakai Review sebelum menampilkan angka final, dan oleh test.
    ///
    /// Menunggu pekerja yang sedang tercatat di `worker` saat dipanggil. Kalau tidak ada
    /// pekerja (antrean memang kosong), langsung kembali — tidak ada yang perlu ditunggu.
    func waitUntilIdle() async {
        await worker?.value
    }

    /// Menghentikan lapang yang belum sempat mulai dianalisis. Lapang yang sedang berjalan
    /// saat ini dibiarkan selesai — hanya yang masih menunggu giliran yang dibuang.
    func cancelAll() {
        generation += 1
        worker?.cancel()
        worker = nil
        jobs.removeAll()
        remaining = 0
    }

    // MARK: - Pekerja

    private func startWorkerIfNeeded() {
        guard worker == nil else { return }

        let myGeneration = generation
        worker = Task { [weak self] in
            await self?.runWorker(generation: myGeneration)
        }
    }

    private func runWorker(generation myGeneration: Int) async {
        // Generasi dicek SEBELUM `takeNextJob()`, dengan sengaja: kalau dicek sesudahnya,
        // pekerja basi bisa mengambil lapang milik generasi baru dari `jobs` lalu berhenti
        // tanpa memprosesnya — lapang itu lenyap, bukan sekadar tertunda.
        while generation == myGeneration, !Task.isCancelled, let job = takeNextJob() {
            let analysis = await analyse(job)
            job.session.setAnalysis(analysis, for: job.fieldID)
            persist(job.session)
            guard generation == myGeneration else { return }
            remaining = jobs.count
        }
        guard generation == myGeneration else { return }
        remaining = jobs.isEmpty ? 0 : jobs.count
        worker = nil
    }

    private func takeNextJob() -> Job? {
        jobs.isEmpty ? nil : jobs.removeFirst()
    }

    /// Menyimpan sesi ke disk setelah satu lapang selesai dianalisis.
    ///
    /// Fire-and-forget dengan sengaja, mengikuti bentuk `ReviewViewModel.persist()`: pekerja
    /// TIDAK menunggu tulisan ini sebelum mengambil lapang berikutnya. Kalau menunggu, laju
    /// antrean akan tersandera I/O disk — persis hal yang ingin dihindari dengan menjalankan
    /// analisis di latar sejak awal. Kegagalan dilaporkan lewat log, bukan dilempar: tidak ada
    /// pihak yang menunggu hasil panggilan ini untuk bisa "membatalkan" apa pun.
    ///
    /// Aman berjalan bersamaan dengan simpanan lain untuk sesi yang sama (mis.
    /// `ReviewViewModel.persist()` kalau analis mengoreksi satu lapang sementara lapang lain
    /// masih diantre) — `SessionStore` tidak punya state bersama antar-panggilan `save`, tiap
    /// panggilan membawa snapshot `ExamSession` yang utuh, dan keduanya adalah `Task` yang
    /// mewarisi `@MainActor` ini, jadi tulisan yang datang belakangan menggantikan yang lebih
    /// dulu, bukan merusaknya.
    private func persist(_ session: ExamSession) {
        Task { [store] in
            do {
                try await store.save(session)
            } catch {
                queueLog.error("Simpan sesi setelah analisis gagal: \(error.localizedDescription)")
            }
        }
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
