import Testing
@testable import Bacilab

/// WHO/IUATLD scales the reading effort to the density: a heavy smear declares itself
/// within ~20 fields, while Negatif and Scanty are only reportable after the full 100.
/// The asymmetry is deliberate — under-reading a sparse slide is what sends an
/// infectious patient home untreated.
struct GradeThresholdTests {

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
        let draft = SampleDraft()
        draft.grade = .negative

        draft.capturedFieldCount = 20
        #expect(!draft.isGradeConfirmed, "Negatif setelah 20 lapang tidak boleh final")
        #expect(draft.fieldsRemainingForGrade == 80)

        draft.capturedFieldCount = 99
        #expect(!draft.isGradeConfirmed)

        draft.capturedFieldCount = 100
        #expect(draft.isGradeConfirmed)
        #expect(draft.fieldsRemainingForGrade == 0)
    }

    @Test("3+ sudah bisa final setelah 20 lapang pandang")
    func heavySmearConfirmsEarly() {
        let draft = SampleDraft()
        draft.grade = .plus3

        draft.capturedFieldCount = 19
        #expect(!draft.isGradeConfirmed)

        draft.capturedFieldCount = 20
        #expect(draft.isGradeConfirmed)
    }

    @Test("Satu lapang pandang tidak pernah menghasilkan grade final")
    func singleFieldIsNeverFinal() {
        for grade in BTAGrade.allCases {
            let draft = SampleDraft()
            draft.grade = grade
            draft.capturedFieldCount = 1

            #expect(!draft.isGradeConfirmed,
                    "\(grade.rawValue) dianggap final hanya dari 1 lapang pandang")
        }
    }

    @Test("Grade sementara ikut naik saat lapang pandang bertambah")
    func thresholdFollowsCurrentGrade() {
        let draft = SampleDraft()
        draft.capturedFieldCount = 30

        // At 30 fields a 3+ reading already stands, but a negative one does not
        draft.grade = .plus3
        #expect(draft.isGradeConfirmed)

        draft.grade = .negative
        #expect(!draft.isGradeConfirmed)
        #expect(draft.fieldsRemainingForGrade == 70)
    }
}
