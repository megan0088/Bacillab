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

    /// Fields currently queued or in flight, so the same one is never analysed twice.
    private var enqueuedIDs: Set<UUID> = []

    func enqueue(fieldID: UUID, imageData: Data, into session: ExamSession) {
        // Review re-queues everything still pending each time it appears, and a queue outlives
        // one visit — leaving Review and coming back would otherwise enqueue the same fields
        // again. That costs N× the inference and pushes `remaining` past the number of fields,
        // which renders as "Analysing -16 of 20 fields…".
        guard enqueuedIDs.insert(fieldID).inserted else { return }

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

    /// Stops the queue and freezes the session against any further analysis.
    ///
    /// A field already mid-flight finishes computing — there is no way to interrupt the model —
    /// but its result is **discarded** rather than written, because the generation it belongs to
    /// is no longer current. That is what lets `publish()` freeze a reading: without it, a field
    /// still in flight would land after the report was published and silently move the total,
    /// the denominator, and the grade while the analyst was looking at the result sheet.
    ///
    /// A discarded field simply stays unanalysed; `ReviewViewModel.analysePendingFields()` picks
    /// it up again on the next visit.
    func cancelAll() {
        generation += 1
        worker?.cancel()
        worker = nil
        jobs.removeAll()
        enqueuedIDs.removeAll()
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

            // Checked BEFORE writing, not after. `analyse` is the long await, so a `cancelAll()`
            // — from publishing, or from the analyst stopping the scan — almost always lands
            // during it. Writing first and checking afterwards would let a cancelled field
            // mutate the session anyway, which is precisely the drift `publish()` must prevent.
            guard generation == myGeneration else { return }

            job.session.setAnalysis(analysis, for: job.fieldID)
            enqueuedIDs.remove(job.fieldID)
            persist(job.session)
            remaining = jobs.count

            // An out-of-memory kill leaves no trace inside the app, so the footprint is logged
            // per field: if it climbs field over field, the queue is accumulating and that is
            // the bug; if it is flat, the abrupt exits are something else entirely and looking
            // at allocations any further is wasted effort.
            queueLog.note(String(format: "lapang selesai, sisa %d, memori %.0f MB",
                                 remaining, Diag.footprintMB))
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
        // Frozen here, on this actor, before the value is sent. Handing the live session to the
        // store would let it read `fields` on the cooperative pool while the scan loop appends
        // to it — a concurrent read/append that corrupts rather than merely miscounts.
        let snapshot = session.snapshot()
        Task { [store] in
            do {
                try await store.save(snapshot)
            } catch {
                queueLog.error("Simpan sesi setelah analisis gagal: \(error.localizedDescription)")
            }
        }
    }

    private func analyse(_ job: Job) async -> FieldAnalysis {
        do {
            let result = try await analysisService.analyze(imageData: job.imageData, using: .resnet)
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
