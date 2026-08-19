import Testing
import Foundation
@testable import Bacilab

/// Seluruh angka sesi adalah turunan dari daftar lapang. Tidak ada akumulator terpisah
/// yang bisa menyimpang dari isinya.
struct ExamSessionTests {

    private func analysis(_ count: Int, failure: String? = nil) -> FieldAnalysis {
        FieldAnalysis(
            readings: [DetectorReading(detector: .yolo, btaCount: count,
                                       confidence: 0.8, elapsed: 0.5, failure: failure)],
            primary: .yolo
        )
    }

    /// Menambahkan `count` lapang, masing-masing dengan hitungan `bta`.
    @discardableResult
    private func fill(_ session: ExamSession, count: Int, bta: Int) -> [FieldRecord] {
        (0..<count).map { _ in
            let field = session.appendField(imageFileName: "f.jpg")
            session.setAnalysis(analysis(bta), for: field.id)
            return field
        }
    }

    @Test("Setiap lapang terhitung, termasuk yang tidak berisi BTA")
    func everyFieldCountsIncludingEmpty() {
        let session = ExamSession()
        fill(session, count: 5, bta: 0)

        #expect(session.examinedFieldCount == 5,
                "Lapang kosong wajib masuk penyebut — tanpa itu Negatif tidak pernah tercapai")
        #expect(session.totalBTA == 0)
        #expect(session.suggestedGrade == .negative)
    }

    @Test("Total BTA dan penyebut dihitung dari lapang")
    func totalsDerivedFromFields() {
        let session = ExamSession()
        fill(session, count: 4, bta: 3)

        #expect(session.examinedFieldCount == 4)
        #expect(session.totalBTA == 12)
    }

    @Test("Koreksi analis langsung mengubah total")
    func correctionChangesTotal() {
        let session = ExamSession()
        let fields = fill(session, count: 3, bta: 5)
        #expect(session.totalBTA == 15)

        session.setCorrectedCount(1, for: fields[0].id)

        #expect(session.totalBTA == 11, "5+5+5 dengan lapang pertama dikoreksi jadi 1")
        #expect(session.examinedFieldCount == 3, "Koreksi tidak mengubah jumlah lapang")
    }

    @Test("Lapang yang dibuang hilang dari pembilang dan penyebut")
    func excludedFieldLeavesBothSides() {
        let session = ExamSession()
        let fields = fill(session, count: 4, bta: 5)

        session.setExcluded(true, for: fields[0].id)

        #expect(session.totalBTA == 15)
        #expect(session.examinedFieldCount == 3,
                "Lapang yang dibuang harus keluar dari penyebut juga, bukan cuma pembilang")
    }

    @Test("Lapang gagal-analisis tidak menyumbang nol ke mana pun")
    func failedFieldContributesToNeither() {
        let session = ExamSession()
        fill(session, count: 3, bta: 6)
        let broken = session.appendField(imageFileName: "f.jpg")
        session.setAnalysis(analysis(0, failure: "ORT gagal"), for: broken.id)

        #expect(session.examinedFieldCount == 3,
                "Lapang gagal tidak boleh menggelembungkan penyebut")
        #expect(session.totalBTA == 18)
        #expect(session.fieldsNeedingManualCount.count == 1)
    }

    @Test("Lapang yang masih diantre belum masuk hitungan")
    func pendingFieldNotCountedYet() {
        let session = ExamSession()
        fill(session, count: 2, bta: 4)
        _ = session.appendField(imageFileName: "f.jpg")

        #expect(session.examinedFieldCount == 2)
        #expect(session.pendingAnalysisCount == 1)
        #expect(session.fields.count == 3, "Lapang tetap tercatat meski analisisnya belum selesai")
    }

    @Test("Grade pilihan analis mengalahkan grade usulan")
    func chosenGradeWins() {
        let session = ExamSession()
        fill(session, count: 10, bta: 2)       // 200 per 100 lapang → 2+

        #expect(session.suggestedGrade == .plus2)
        #expect(session.reportedGrade == .plus2)

        session.chooseGrade(.scanty)

        #expect(session.reportedGrade == .scanty)
        #expect(session.suggestedGrade == .plus2, "Usulan model tidak ikut berubah")
    }

    @Test("Negatif belum final sebelum 100 lapang")
    func negativeNeedsFullReading() {
        let session = ExamSession()
        fill(session, count: 20, bta: 0)

        #expect(session.reportedGrade == .negative)
        #expect(!session.isGradeConfirmed)
        #expect(session.fieldsRemainingForGrade == 80)
    }

    @Test("3+ sudah final di 20 lapang")
    func heavySmearConfirmsAtTwenty() {
        let session = ExamSession()
        fill(session, count: 20, bta: 15)      // 1500 per 100 lapang → 3+

        #expect(session.reportedGrade == .plus3)
        #expect(session.isGradeConfirmed)
        #expect(session.fieldsRemainingForGrade == 0)
    }

    @Test("Gerbang mengikuti grade yang dipilih, bukan yang diusulkan")
    func gateFollowsChosenGrade() {
        let session = ExamSession()
        fill(session, count: 20, bta: 15)      // usulan 3+, sudah final
        #expect(session.isGradeConfirmed)

        session.chooseGrade(.scanty)

        #expect(!session.isGradeConfirmed, "Scanty butuh 100 lapang meski usulannya 3+")
        #expect(session.fieldsRemainingForGrade == 80)
    }

    @Test("Membuang lapang bisa membatalkan status final")
    func exclusionCanUnconfirmGrade() {
        let session = ExamSession()
        let fields = fill(session, count: 20, bta: 15)
        #expect(session.isGradeConfirmed)

        session.setExcluded(true, for: fields[0].id)

        #expect(session.examinedFieldCount == 19)
        #expect(!session.isGradeConfirmed,
                "19 lapang tidak cukup untuk 3+ — status final harus ikut turun")
    }

    @Test("Status beranda diturunkan dari status sesi")
    func displayStatusDerivation() {
        let session = ExamSession()
        #expect(session.displayStatus == .running)

        fill(session, count: 20, bta: 15)
        session.status = .reviewing
        #expect(session.displayStatus == .running)

        session.status = .published
        #expect(session.displayStatus == .positive)

        session.chooseGrade(.negative)
        #expect(session.displayStatus == .negative)
    }

    @Test("Sesi kosong tidak meledak")
    func emptySessionIsSafe() {
        let session = ExamSession()

        #expect(session.examinedFieldCount == 0)
        #expect(session.totalBTA == 0)
        #expect(session.suggestedGrade == .negative)
        #expect(!session.isGradeConfirmed)
    }
}
