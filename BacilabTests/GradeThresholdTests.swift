import Testing
@testable import Bacilab

/// WHO/IUATLD menskalakan beban baca pada kepadatan: smear berat mengumumkan dirinya dalam
/// ~20 lapang, sedangkan Negatif dan Scanty baru boleh dilaporkan setelah 100 lapang penuh.
/// Asimetrinya disengaja — membaca terlalu sedikit pada slide yang jarang adalah yang
/// memulangkan pasien menular tanpa pengobatan.
struct GradeThresholdTests {

    private func session(fieldCount: Int, btaPerField: Int) -> ExamSession {
        let session = ExamSession()
        for _ in 0..<fieldCount {
            let field = session.appendField(imageFileName: "f.jpg")
            session.setAnalysis(
                FieldAnalysis(
                    readings: [DetectorReading(detector: .resnet, btaCount: btaPerField,
                                               confidence: 0.8, elapsed: 0.4)],
                    primary: .resnet),
                for: field.id)
        }
        return session
    }

    @Test("Ambang lapang pandang sesuai WHO/IUATLD")
    func minimumFieldsPerGrade() {
        #expect(BTAGrade.plus3.minimumFields == 20)
        #expect(BTAGrade.plus2.minimumFields == 50)
        #expect(BTAGrade.plus1.minimumFields == 100)
        #expect(BTAGrade.scanty.minimumFields == 100)
        #expect(BTAGrade.negative.minimumFields == 100)
    }

    @Test("Negatif tidak boleh final sebelum 100 lapang pandang")
    func negativeNeedsFullReading() {
        let twenty = session(fieldCount: 20, btaPerField: 0)
        #expect(twenty.reportedGrade == .negative)
        #expect(!twenty.isGradeConfirmed, "Negatif setelah 20 lapang tidak boleh final")
        #expect(twenty.fieldsRemainingForGrade == 80)

        let ninetyNine = session(fieldCount: 99, btaPerField: 0)
        #expect(!ninetyNine.isGradeConfirmed)

        let hundred = session(fieldCount: 100, btaPerField: 0)
        #expect(hundred.isGradeConfirmed)
        #expect(hundred.fieldsRemainingForGrade == 0)
    }

    @Test("3+ sudah bisa final setelah 20 lapang pandang")
    func heavySmearConfirmsEarly() {
        #expect(!session(fieldCount: 19, btaPerField: 15).isGradeConfirmed)
        #expect(session(fieldCount: 20, btaPerField: 15).isGradeConfirmed)
    }

    @Test("Satu lapang pandang tidak pernah menghasilkan grade final")
    func singleFieldIsNeverFinal() {
        for grade in BTAGrade.allCases {
            let s = session(fieldCount: 1, btaPerField: 5)
            s.chooseGrade(grade)
            #expect(!s.isGradeConfirmed,
                    "\(grade.rawValue) dianggap final hanya dari 1 lapang pandang")
        }
    }

    @Test("Ambang mengikuti grade yang sedang berlaku")
    func thresholdFollowsCurrentGrade() {
        let s = session(fieldCount: 30, btaPerField: 15)

        s.chooseGrade(.plus3)
        #expect(s.isGradeConfirmed)

        s.chooseGrade(.negative)
        #expect(!s.isGradeConfirmed)
        #expect(s.fieldsRemainingForGrade == 70)
    }
}
