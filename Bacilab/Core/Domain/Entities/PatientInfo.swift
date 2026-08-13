import Foundation

/// Identitas pasien dan sampelnya, sesuai form hi-fi.
///
/// Tidak ada nama dokter dan nomor akses di sini: keduanya dikumpulkan oleh form lama
/// tapi tidak pernah ditampilkan di layar mana pun.
struct PatientInfo: Codable, Hashable, Sendable {
    var medicalRecordNumber = ""
    var nationalID = ""
    var name = ""
    var dateOfBirth = Date()
    var address = ""
    var phone = ""
    var examinationDate = Date()
    var sampleCollectedAt = Date()

    /// Cukup untuk memulai sesi. Nama dan nomor rekam medis wajib karena keduanya yang
    /// dipakai menemukan kembali hasil ini; sisanya boleh menyusul.
    var isComplete: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !medicalRecordNumber.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
