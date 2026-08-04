import Foundation
import Observation

@Observable
final class SampleDraft {
    // Patient information
    var patientName = ""
    var accessionNumber = ""
    var dateOfBirth = Date()
    var doctorName = ""
    var phone = ""
    var address = ""
    var examinationDate = Date()

    // Legacy / compatibility
    var patientID = ""
    var sampleType = ""
    var collectedAt = Date()

    // Capture state
    var imageData: Data?
    var capturedFieldCount = 0
    let totalFieldCount = 100

    // Analysis state (AI + manual)
    var manualBTACount = 0
    var aiConfidence: Double = 0
    var grade: BTAGrade = .negative
    var notes = ""

    /// Set once the technician picks a grade by hand. While true, further captures
    /// stop recomputing `grade`, so a deliberate clinical judgement is never silently
    /// replaced by the extrapolated one.
    var hasManualGrade = false

    /// Records a grade chosen by a person rather than derived from the count.
    func selectGrade(_ grade: BTAGrade) {
        self.grade = grade
        hasManualGrade = true
    }

    /// Whether enough fields have been read for `grade` to stand as a final report.
    /// Until this is true the reading is provisional, however confident the detector is.
    var isGradeConfirmed: Bool {
        capturedFieldCount >= grade.minimumFields
    }

    /// Fields still to be read before the current grade may be reported.
    var fieldsRemainingForGrade: Int {
        max(0, grade.minimumFields - capturedFieldCount)
    }
}
