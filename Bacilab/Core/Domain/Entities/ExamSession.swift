import Foundation
import Observation

enum SessionStatus: String, Codable, Hashable, Sendable {
    case scanning
    case reviewing
    case published
}

/// Bagaimana sebuah sesi tampil di beranda.
enum SessionDisplayStatus: Hashable, Sendable {
    case running
    case negative
    case positive

    var label: String {
        switch self {
        case .running:  return "In progress"
        case .negative: return "Negative"
        case .positive: return "Positive"
        }
    }
}

/// Satu pemeriksaan, dari data pasien sampai hasil terbit.
///
/// **Tidak ada angka yang disimpan.** `totalBTA` dan `examinedFieldCount` dihitung ulang dari
/// `fields` setiap kali dibaca. Model lama menyimpan `manualBTACount` terpisah dari daftar
/// lapang, sehingga keduanya bisa menyimpang — dan yang menentukan grade pasien adalah yang
/// tersimpan, bukan yang terlihat. Di sini penyimpangan itu tidak punya tempat untuk terjadi.
@Observable
final class ExamSession: Identifiable {

    /// Berapa lapang yang dituju satu batch scan. **Tidak pernah** ikut perhitungan grading —
    /// ia hanya mengisi teks "n dari 20" di layar scan. Penyebut grading adalah
    /// `examinedFieldCount`.
    static let batchTarget = 20

    let id: UUID
    let createdAt: Date
    var patient: PatientInfo
    var notes: String
    var status: SessionStatus

    /// Grade yang dipilih analis. `nil` berarti belum ada yang memutuskan, sehingga
    /// `reportedGrade` jatuh ke usulan model. Optional inilah yang menggantikan
    /// `hasManualGrade` lama — tidak perlu flag terpisah untuk membedakan "belum diputuskan"
    /// dari "diputuskan manusia".
    private(set) var chosenGrade: BTAGrade?

    private(set) var fields: [FieldRecord]

    init(
        id: UUID = UUID(),
        patient: PatientInfo = PatientInfo(),
        notes: String = "",
        status: SessionStatus = .scanning,
        chosenGrade: BTAGrade? = nil,
        fields: [FieldRecord] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.patient = patient
        self.notes = notes
        self.status = status
        self.chosenGrade = chosenGrade
        self.fields = fields
        self.createdAt = createdAt
    }

    // MARK: - Mutasi

    /// Mencatat satu lapang baru. Selalu bertambah — apa pun isinya, termasuk lapang kosong.
    ///
    /// Inilah perbaikan atas cacat lama: auto-scan dulu hanya menambah hitungan ketika
    /// `btaCount > 0`, sehingga lapang kosong tidak pernah masuk penyebut dan grade Negatif
    /// secara struktural tidak bisa dicapai.
    @discardableResult
    func appendField(imageFileName: String, source: FieldSource = .camera) -> FieldRecord {
        let field = FieldRecord(index: fields.count, imageFileName: imageFileName, source: source)
        fields.append(field)
        return field
    }

    func setAnalysis(_ analysis: FieldAnalysis, for fieldID: UUID) {
        guard let i = fields.firstIndex(where: { $0.id == fieldID }) else { return }
        fields[i].analysis = analysis
    }

    /// `nil` mengembalikan lapang ke hitungan model.
    func setCorrectedCount(_ count: Int?, for fieldID: UUID) {
        guard let i = fields.firstIndex(where: { $0.id == fieldID }) else { return }
        fields[i].correctedCount = count.map { max(0, $0) }
    }

    func setExcluded(_ excluded: Bool, for fieldID: UUID) {
        guard let i = fields.firstIndex(where: { $0.id == fieldID }) else { return }
        fields[i].isExcluded = excluded
    }

    func chooseGrade(_ grade: BTAGrade) {
        chosenGrade = grade
    }

    func field(withID id: UUID) -> FieldRecord? {
        fields.first { $0.id == id }
    }

    // MARK: - Turunan

    /// Lapang yang masuk hitungan: tidak dibuang, dan punya angka.
    var countedFields: [FieldRecord] { fields.filter(\.isCounted) }

    /// Penyebut grading — berapa lapang benar-benar terbaca.
    var examinedFieldCount: Int { countedFields.count }

    var totalBTA: Int { countedFields.compactMap(\.effectiveCount).reduce(0, +) }

    /// Grade yang dihitung dari lapang. `max(_, 1)` hanya menjaga pembagian nol; dengan
    /// nol lapang `totalBTA` juga nol, jadi hasilnya tetap Negatif.
    var suggestedGrade: BTAGrade {
        BTAGrade.grade(for: totalBTA, across: max(examinedFieldCount, 1))
    }

    /// Grade yang dilaporkan: pilihan analis kalau ada, usulan model kalau tidak.
    var reportedGrade: BTAGrade { chosenGrade ?? suggestedGrade }

    /// Apakah lapang sudah cukup untuk grade ini berdiri sebagai laporan final (WHO/IUATLD).
    var isGradeConfirmed: Bool { examinedFieldCount >= reportedGrade.minimumFields }

    var fieldsRemainingForGrade: Int {
        max(0, reportedGrade.minimumFields - examinedFieldCount)
    }

    var pendingAnalysisCount: Int { fields.filter(\.isPending).count }

    var fieldsNeedingManualCount: [FieldRecord] { fields.filter(\.needsManualCount) }

    /// How many counted fields came from imported photos rather than the eyepiece.
    ///
    /// Surfaced so a mixed session declares itself: a slide read partly from the microscope and
    /// partly from imported images is two acquisitions pooled into one grade, and a reader of
    /// the result sheet has no other way to tell.
    var importedFieldCount: Int { countedFields.filter { $0.source == .gallery }.count }

    var displayStatus: SessionDisplayStatus {
        switch status {
        case .scanning, .reviewing:
            return .running
        case .published:
            return reportedGrade == .negative ? .negative : .positive
        }
    }
}

extension ExamSession: Hashable {
    static func == (lhs: ExamSession, rhs: ExamSession) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
