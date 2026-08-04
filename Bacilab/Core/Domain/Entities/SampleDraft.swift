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
}
