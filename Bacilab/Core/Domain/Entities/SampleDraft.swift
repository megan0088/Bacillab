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

    /// Running totals per model, over the fields each one actually read.
    ///
    /// One accumulator **per detector**, not one shared accumulator relabelled at display
    /// time. There used to be a single `comparisonBTACount` paired with `manualBTACount`, and
    /// which model each belonged to depended on what was selected when the column was drawn.
    /// Switching from "Keduanya" to YOLO therefore relabelled ResNet's accumulated fields as
    /// YOLO's: the heading changed, the number did not. Keyed totals make that impossible —
    /// a count can only ever be filed under the model that produced it.
    private(set) var detectorCounts: [DetectorKind: Int] = [:]
    private(set) var detectorFields: [DetectorKind: Int] = [:]

    /// That model's running BTA total. 0 also means "never ran" — pair it with `fields(for:)`.
    func count(for detector: DetectorKind) -> Int { detectorCounts[detector] ?? 0 }

    /// How many fields that model actually read, which is what separates "counted nothing"
    /// from "never ran".
    func fields(for detector: DetectorKind) -> Int { detectorFields[detector] ?? 0 }

    /// Files one field's readings under the models that produced them. Readings marked
    /// `failure` are skipped, so a field a model could not read does not enter its total
    /// as a zero and drag its average down.
    func record(_ readings: [DetectorReading]) {
        for reading in readings where reading.failure == nil {
            detectorCounts[reading.detector, default: 0] += reading.btaCount
            detectorFields[reading.detector, default: 0] += 1
        }
    }

    /// Every field read so far, newest last, so the analyst can go back and look at one.
    ///
    /// A count of 100 fields is a long session, and until now only the most recent frame
    /// survived — there was no way to check a field that had already scrolled past, which is
    /// exactly what someone doubting a number wants to do.
    private(set) var capturedFields: [CapturedField] = []

    /// Files a field's image alongside its readings.
    func record(_ readings: [DetectorReading], image: Data?, source: FieldSource) {
        record(readings)
        guard let image else { return }
        capturedFields.append(
            CapturedField(image: image, readings: readings, source: source)
        )
    }

    /// Re-points the count of record at one model's own total.
    ///
    /// Called when the analyst switches models mid-sample. Without it `manualBTACount` keeps
    /// the fields read by the previous model and adds the new model's on top — a total no
    /// single detector ever produced, on the number that becomes the patient's grade. Any
    /// manual +/- adjustment is dropped deliberately: it was made against a different model's
    /// reading of different fields, so carrying it over would be worse than losing it.
    func adoptCount(from detector: DetectorKind) {
        countSource = detector
        manualBTACount = count(for: detector)
        guard !hasManualGrade else { return }
        grade = BTAGrade.grade(for: manualBTACount, across: max(fields(for: detector), 1))
    }

    /// Which model `manualBTACount` currently represents.
    private(set) var countSource: DetectorKind = .resnet

    /// Makes sure the count of record belongs to `detector` before another field is added.
    ///
    /// This lives here rather than in a view's `onChange` because it is an invariant of the
    /// data, not of the screen: it has to hold whether or not the capture view happens to be
    /// on display. Wired to the view alone, a selection changed through any other path would
    /// silently fold one model's fields into another model's running total.
    func reconcileCountSource(with detector: DetectorKind) {
        guard countSource != detector else { return }
        adoptCount(from: detector)
    }

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
