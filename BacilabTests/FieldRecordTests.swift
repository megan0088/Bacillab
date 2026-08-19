import Testing
import Foundation
@testable import Bacilab

/// Satu lapang boleh berada dalam empat keadaan: belum dianalisis, dianalisis dengan
/// hasil, dianalisis tapi gagal, atau dibuang analis. Hanya keadaan kedua dan lapang
/// yang dikoreksi manual yang boleh masuk hitungan.
struct FieldRecordTests {

    private func reading(_ count: Int, failure: String? = nil) -> DetectorReading {
        DetectorReading(detector: .yolo, btaCount: count, confidence: 0.8,
                        elapsed: 0.5, failure: failure)
    }

    private func field(
        index: Int = 0,
        analysis: FieldAnalysis? = nil,
        corrected: Int? = nil,
        excluded: Bool = false
    ) -> FieldRecord {
        FieldRecord(index: index, imageFileName: "field-000.jpg",
                    analysis: analysis, correctedCount: corrected, isExcluded: excluded)
    }

    @Test("Lapang tanpa analisis belum punya hitungan")
    func pendingFieldHasNoCount() {
        let f = field()
        #expect(f.effectiveCount == nil)
        #expect(f.isPending)
        #expect(!f.isCounted)
    }

    @Test("Hitungan model dipakai ketika tidak ada koreksi")
    func modelCountUsedWhenNotCorrected() {
        let f = field(analysis: FieldAnalysis(readings: [reading(9)], primary: .yolo))
        #expect(f.effectiveCount == 9)
        #expect(f.isCounted)
    }

    @Test("Koreksi analis mengalahkan hitungan model")
    func correctionWins() {
        let f = field(analysis: FieldAnalysis(readings: [reading(9)], primary: .yolo),
                      corrected: 4)
        #expect(f.effectiveCount == 4)
    }

    @Test("Koreksi nol adalah nol, bukan 'belum dikoreksi'")
    func zeroCorrectionIsRespected() {
        let f = field(analysis: FieldAnalysis(readings: [reading(9)], primary: .yolo),
                      corrected: 0)
        #expect(f.effectiveCount == 0, "Nol dari analis harus menang atas 9 dari model")
        #expect(f.isCounted)
    }

    @Test("Analisis gagal tidak pernah bernilai nol")
    func failedAnalysisHasNoCount() {
        let f = field(analysis: FieldAnalysis(
            readings: [reading(0, failure: "ORT gagal")], primary: .yolo))
        #expect(f.effectiveCount == nil, "Kegagalan tidak boleh terbaca sebagai 'tidak lihat apa-apa'")
        #expect(f.needsManualCount)
        #expect(!f.isCounted)
    }

    @Test("Lapang gagal yang dikoreksi manual kembali terhitung")
    func failedFieldRecoveredByCorrection() {
        let f = field(analysis: FieldAnalysis(
            readings: [reading(0, failure: "ORT gagal")], primary: .yolo), corrected: 3)
        #expect(f.effectiveCount == 3)
        #expect(f.isCounted)
        #expect(!f.needsManualCount)
    }

    @Test("Lapang yang dibuang tidak terhitung meski punya angka")
    func excludedFieldIsNotCounted() {
        let f = field(analysis: FieldAnalysis(readings: [reading(12)], primary: .yolo),
                      excluded: true)
        #expect(!f.isCounted)
        #expect(!f.needsManualCount, "Lapang yang dibuang tidak perlu dihitung manual")
    }

    @Test("Lapang yang dibuang sebelum dianalisis tidak dianggap masih mengantre")
    func excludedBeforeAnalysisIsNotPending() {
        let f = field(excluded: true)
        #expect(!f.isPending, "Lapang yang sudah dibuang bukan lapang yang menunggu giliran")
        #expect(!f.isCounted)
        #expect(!f.needsManualCount)
        #expect(f.effectiveCount == nil)
    }

    @Test("Data pasien lengkap butuh nama dan nomor rekam medis")
    func patientCompleteness() {
        var p = PatientInfo()
        #expect(!p.isComplete)
        p.name = "Ahmad Rizki"
        #expect(!p.isComplete)
        p.medicalRecordNumber = "RM 240724-001"
        #expect(p.isComplete)
        p.name = "   "
        #expect(!p.isComplete, "Spasi saja bukan nama")
    }
}
