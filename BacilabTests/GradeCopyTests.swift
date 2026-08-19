import Testing
@testable import Bacilab

/// Satu grade harus punya satu nama di seluruh app. Sebelumnya ada tiga: "1+" di Review,
/// "Positive 1+" di riwayat, "Positive (1+)" di lembar hasil — untuk slide yang sama.
struct GradeCopyTests {

    @Test("Setiap grade punya satu nama tampilan")
    func displayNames() {
        #expect(BTAGrade.negative.displayName == "Negative")
        #expect(BTAGrade.scanty.displayName == "Scanty")
        #expect(BTAGrade.plus1.displayName == "Positive 1+")
        #expect(BTAGrade.plus2.displayName == "Positive 2+")
        #expect(BTAGrade.plus3.displayName == "Positive 3+")
    }

    /// `rawValue` adalah kunci penyimpanan di manifest.json. Kalau ini berubah, setiap sesi
    /// yang sudah tersimpan gagal di-decode — dan SessionStore melewatkan manifest yang tidak
    /// bisa dibaca, jadi sesi itu hilang dari daftar, bukan memunculkan error.
    @Test("rawValue tidak ikut berubah bersama nama tampilan")
    func rawValuesUnchanged() {
        #expect(BTAGrade.negative.rawValue == "Negative")
        #expect(BTAGrade.scanty.rawValue == "Scanty")
        #expect(BTAGrade.plus1.rawValue == "1+")
        #expect(BTAGrade.plus2.rawValue == "2+")
        #expect(BTAGrade.plus3.rawValue == "3+")
    }

    @Test("Setiap grade punya kriteria WHO/IUATLD yang terisi")
    func everyGradeHasACriterion() {
        for grade in BTAGrade.allCases {
            #expect(!grade.criterion.isEmpty, "\(grade.rawValue) tidak punya kriteria")
        }
    }

    /// Negatif dan Scanty menuntut 100 lapang penuh; kriterianya harus menyebut itu, karena
    /// kalimat inilah yang dibaca orang saat memutuskan apakah hasil boleh dilaporkan.
    @Test("Kriteria menyebut jumlah lapang untuk grade yang menuntut 100")
    func criterionMentionsFieldCount() {
        #expect(BTAGrade.negative.criterion.contains("100"))
        #expect(BTAGrade.scanty.criterion.contains("100"))
    }
}
