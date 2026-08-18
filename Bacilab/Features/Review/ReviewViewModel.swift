import Foundation
import Observation
import UIKit

private let reviewLog = Diag("review")

/// Satu-satunya layar yang memutuskan: berapa BTA di tiap lapang, lapang mana yang dibuang,
/// grade apa yang dilaporkan, dan kapan hasilnya terbit.
///
/// Setiap koreksi langsung mengubah sesi dan langsung tersimpan. Tidak ada tombol simpan yang
/// bisa terlewat, jadi tidak pernah ada keadaan di mana angka di layar berbeda dari angka
/// yang tersimpan.
@MainActor
@Observable
final class ReviewViewModel {

    let session: ExamSession
    let queue: FieldAnalysisQueue
    private let store: any SessionStoreProtocol

    var selectedFieldID: UUID?
    var keypadText = ""
    var isKeypadPresented = false
    var errorMessage: String?
    var isPublishing = false
    private(set) var isPublished = false

    /// Hitungan satu lapang tidak pernah mencapai lima digit; batas ini hanya menahan
    /// ketukan beruntun yang tidak disengaja.
    private let maxKeypadDigits = 4

    init(
        session: ExamSession,
        store: any SessionStoreProtocol,
        queue: FieldAnalysisQueue
    ) {
        self.session = session
        self.store = store
        self.queue = queue
        self.selectedFieldID = session.fields.first?.id
    }

    // MARK: - Navigasi

    var selectedField: FieldRecord? {
        guard let selectedFieldID else { return session.fields.first }
        return session.field(withID: selectedFieldID)
    }

    var selectedIndex: Int {
        guard let selectedField else { return 0 }
        return session.fields.firstIndex { $0.id == selectedField.id } ?? 0
    }

    func select(_ id: UUID) { selectedFieldID = id }

    func selectNext() {
        let next = min(selectedIndex + 1, session.fields.count - 1)
        guard next >= 0, session.fields.indices.contains(next) else { return }
        selectedFieldID = session.fields[next].id
    }

    func selectPrevious() {
        let previous = max(selectedIndex - 1, 0)
        guard session.fields.indices.contains(previous) else { return }
        selectedFieldID = session.fields[previous].id
    }

    // MARK: - Keypad

    func openKeypad() {
        keypadText = ""
        isKeypadPresented = true
    }

    func appendDigit(_ digit: String) {
        guard keypadText.count < maxKeypadDigits else { return }
        keypadText.append(digit)
    }

    func deleteDigit() {
        guard !keypadText.isEmpty else { return }
        keypadText.removeLast()
    }

    func cancelKeypad() {
        keypadText = ""
        isKeypadPresented = false
    }

    /// Menyimpan angka yang diketik sebagai hitungan lapang terpilih.
    ///
    /// Keypad kosong sengaja tidak melakukan apa-apa: mengosongkan lalu menekan konfirmasi
    /// bukan cara menyatakan "nol". Untuk nol, ketik `0` — dan nol itu memang tersimpan
    /// sebagai nol, bukan diabaikan sebagai "tidak ada koreksi".
    func commitKeypad() {
        defer { isKeypadPresented = false }
        guard let field = selectedField, let value = Int(keypadText) else {
            keypadText = ""
            return
        }
        session.setCorrectedCount(value, for: field.id)
        keypadText = ""
        persist()
    }

    /// Mengembalikan lapang ke hitungan model.
    func clearCorrection() {
        guard let field = selectedField else { return }
        session.setCorrectedCount(nil, for: field.id)
        persist()
    }

    // MARK: - Lapang

    func toggleExcludedOnSelected() {
        guard let field = selectedField else { return }
        session.setExcluded(!field.isExcluded, for: field.id)
        persist()
    }

    // MARK: - Grade

    func chooseGrade(_ grade: BTAGrade) {
        session.chooseGrade(grade)
        persist()
    }

    // MARK: - Terbit

    /// Lapang yang belum punya angka: gagal dianalisis, atau masih menunggu antrean.
    /// Keduanya keluar dari pembilang dan penyebut, jadi analis harus tahu sebelum terbit.
    var unresolvedFields: [FieldRecord] {
        session.fields.filter { !$0.isExcluded && $0.effectiveCount == nil }
    }

    func publish() async {
        isPublishing = true
        defer { isPublishing = false }

        // Freeze the reading before recording it. Publishing is offered even while fields are
        // still queued — that is what the "Publish Anyway" dialog exists for — and without this
        // those fields land afterwards, moving the total, the denominator and, when no grade was
        // chosen by hand, the grade itself, all while the analyst is looking at the published
        // sheet. Nothing would record that it changed. Discarded fields stay unanalysed and are
        // picked up again by `analysePendingFields()` if the analyst returns to Review.
        queue.cancelAll()

        let previousStatus = session.status
        session.status = .published
        do {
            errorMessage = nil
            try await store.save(session.snapshot())
            isPublished = true
        } catch {
            // Kembalikan statusnya: hasil yang gagal tersimpan tidak boleh tampak terbit.
            session.status = previousStatus
            errorMessage = error.localizedDescription
            reviewLog.error("Terbit gagal: \(error.localizedDescription)")
        }
    }

    // MARK: - Gambar

    /// Queues every field that still has no analysis.
    ///
    /// Two situations reach this screen looking identical: a session resumed after the app was
    /// killed while the queue was still draining, and a seeded demo session whose fields were
    /// never analysed at all. In both, the images are on disk and the models are idle, but
    /// nothing would otherwise enqueue them — the queue only ever receives what `ScanViewModel`
    /// captures live. Without this those fields sit `pending` forever and quietly sit outside
    /// both the numerator and the denominator.
    ///
    /// Safe to call repeatedly, and across visits: `FieldAnalysisQueue` refuses a field id it is
    /// already holding. Relying on `isPending` alone would not be enough — a queue outlives one
    /// visit to this screen, so leaving and returning would enqueue the same still-pending fields
    /// a second time.
    func analysePendingFields() {
        let pending = session.fields.filter(\.isPending)
        guard !pending.isEmpty else { return }

        for field in pending {
            guard let data = imageData(for: field) else {
                reviewLog.error("Field \(field.index) has no image on disk; cannot analyse it")
                continue
            }
            queue.enqueue(fieldID: field.id, imageData: data, into: session)
        }
        reviewLog.note("Queued \(pending.count) unanalysed field(s)")
    }

    func imageData(for field: FieldRecord) -> Data? {
        try? Data(contentsOf: store.fieldImageURL(fileName: field.imageFileName, for: session))
    }

    /// One decoded field image, held so the view body does not re-read and re-decode it.
    ///
    /// Only the selected field is ever drawn, so a single entry is enough — caching all 20
    /// would hold roughly 200 MB of decoded bitmaps.
    private var cachedImage: (fieldID: UUID, image: UIImage)?

    /// The selected field's image, decoded at most once per field.
    ///
    /// `ExamSession` is `@Observable` and mutates once per analysed field, and `queue.remaining`
    /// changes alongside it — so during a 20-field run SwiftUI re-evaluates this screen dozens of
    /// times. Decoding a 1600×1600 JPEG from disk inside the body on each of those passes stalls
    /// the main thread and churns memory hard enough to take the app down mid-progress.
    func image(for field: FieldRecord) -> UIImage? {
        if let cachedImage, cachedImage.fieldID == field.id {
            return cachedImage.image
        }
        guard let data = imageData(for: field), let image = UIImage(data: data) else {
            return nil
        }
        cachedImage = (field.id, image)
        return image
    }

    // MARK: - Simpan

    /// Autosave setelah setiap perubahan. Kegagalannya dilaporkan tapi tidak membatalkan
    /// perubahan di memori — analis tetap melihat apa yang baru saja ia ketik.
    private func persist() {
        Task { [weak self] in
            guard let self else { return }
            do {
                self.errorMessage = nil
                try await self.store.save(self.session.snapshot())
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }
}
