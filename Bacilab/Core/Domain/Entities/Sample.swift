import Foundation

struct Sample: Identifiable, Hashable, Sendable {
    let id: UUID
    var patientName: String
    var accessionNumber: String
    var dateOfBirth: Date
    var patientID: String
    var doctorName: String
    var phone: String
    var address: String
    var examinationDate: Date
    var sampleType: String
    var collectedAt: Date
    var imageData: Data?
    var capturedFieldCount: Int
    var totalFieldCount: Int
    var analysisResult: AnalysisResult?
    var notes: String

    init(
        id: UUID = UUID(),
        patientName: String,
        accessionNumber: String = "",
        dateOfBirth: Date = Date(),
        patientID: String = "",
        doctorName: String = "",
        phone: String = "",
        address: String = "",
        examinationDate: Date = Date(),
        sampleType: String = "",
        collectedAt: Date = Date(),
        capturedFieldCount: Int = 0,
        totalFieldCount: Int = 100,
        notes: String = ""
    ) {
        self.id = id
        self.patientName = patientName
        self.accessionNumber = accessionNumber
        self.dateOfBirth = dateOfBirth
        self.patientID = patientID
        self.doctorName = doctorName
        self.phone = phone
        self.address = address
        self.examinationDate = examinationDate
        self.sampleType = sampleType
        self.collectedAt = collectedAt
        self.capturedFieldCount = capturedFieldCount
        self.totalFieldCount = totalFieldCount
        self.notes = notes
    }

    var status: SampleStatus {
        guard let result = analysisResult else { return .pending }
        return result.grade == .negative ? .negative : .positive
    }

    static func build(from draft: SampleDraft) -> Sample {
        var s = Sample(
            patientName: draft.patientName,
            accessionNumber: draft.accessionNumber,
            dateOfBirth: draft.dateOfBirth,
            patientID: draft.patientID,
            doctorName: draft.doctorName,
            phone: draft.phone,
            address: draft.address,
            examinationDate: draft.examinationDate,
            sampleType: draft.sampleType,
            collectedAt: draft.collectedAt,
            capturedFieldCount: draft.capturedFieldCount,
            totalFieldCount: draft.totalFieldCount,
            notes: draft.notes
        )
        s.imageData = draft.imageData
        s.analysisResult = AnalysisResult(
            btaCount: draft.manualBTACount,
            confidence: draft.aiConfidence,
            grade: draft.grade,
            analyzedAt: Date()
        )
        return s
    }
}

enum SampleStatus: String, Sendable {
    case pending  = "Pending"
    case negative = "Negatif"
    case positive = "Positif"

    var color: String {
        switch self {
        case .pending:  return "orange"
        case .negative: return "green"
        case .positive: return "red"
        }
    }
}
