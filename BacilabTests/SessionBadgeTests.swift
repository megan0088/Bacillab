import SwiftUI
import Testing
@testable import Bacilab

/// Badge riwayat memutuskan apakah sebuah grade boleh tampil sebagai kesimpulan. Sebelumnya
/// logika itu privat di dalam sebuah View, jadi tidak ada test yang bisa menyentuhnya.
struct SessionBadgeTests {

    /// Sesi dengan `fields` lapang, tiap lapang `bta` basil, sudah terbit.
    private func published(fields: Int, bta: Int) -> ExamSession {
        let session = ExamSession()
        for _ in 0..<fields {
            let field = session.appendField(imageFileName: "f.jpg")
            session.setAnalysis(
                FieldAnalysis(
                    readings: [DetectorReading(detector: .yolo, btaCount: bta,
                                               confidence: 0.8, elapsed: 0.4)],
                    primary: .yolo),
                for: field.id)
        }
        session.status = .published
        return session
    }

    @Test("Sesi yang belum terbit tampil sebagai In progress")
    func unpublishedReadsAsInProgress() {
        let badge = SessionBadge(session: ExamSession())
        #expect(badge.text == "In progress")
    }

    @Test("Sesi terbit memakai nama tampilan grade, bukan rawValue")
    func publishedUsesDisplayName() {
        // 20 lapang × 15 basil = 1500 per 100 lapang -> 3+, dan 3+ final pada 20 lapang.
        let badge = SessionBadge(session: published(fields: 20, bta: 15))
        #expect(badge.text == "Positive 3+")
    }

    @Test("Grade final memakai warna grade-nya sendiri")
    func confirmedGradeUsesItsOwnTint() {
        let badge = SessionBadge(session: published(fields: 20, bta: 15))
        #expect(badge.tint == BTAGrade.plus3.tint)
    }

    @Test("Grade di bawah ambang lapang tampil Provisional saat switch demo mati")
    func belowFieldGateReadsAsProvisionalWhenDemoSwitchIsOff() {
        // 5 lapang, 0 basil -> suggestedGrade Negatif, tapi Negatif butuh 100 lapang penuh.
        let badge = SessionBadge(session: published(fields: 5, bta: 0), hidesProvisionalMarks: false)
        #expect(badge.text == "Negative · Provisional")
        #expect(badge.tint == .orange)
    }

    @Test("Switch demo menyembunyikan tanda Provisional pada sesi yang sama")
    func demoSwitchHidesProvisionalMark() {
        let badge = SessionBadge(session: published(fields: 5, bta: 0), hidesProvisionalMarks: true)
        #expect(badge.text == "Negative")
    }
}
