import Foundation

// MARK: - Sample preview fixtures

extension Sample {
    static let previews: [Sample] = [
        {
            var s = Sample(
                patientName:     "Ahmad Rizki",
                accessionNumber: "ACC-2025-001",
                dateOfBirth:     Calendar.current.date(byAdding: .year, value: -35, to: Date()) ?? Date(),
                patientID:       "RM-001234",
                doctorName:      "dr. Sari Dewi",
                phone:           "0812-3456-7890",
                address:         "Jl. Merdeka No. 12, Jakarta",
                examinationDate: Date(),
                sampleType:      "Dahak",
                capturedFieldCount: 12,
                totalFieldCount: 100
            )
            s.analysisResult = AnalysisResult(
                btaCount: 16,
                confidence: 0.90,
                grade: .plus2,
                analyzedAt: Date()
            )
            return s
        }(),
        {
            var s = Sample(
                patientName:     "Budi Santoso",
                accessionNumber: "ACC-2025-002",
                dateOfBirth:     Calendar.current.date(byAdding: .year, value: -45, to: Date()) ?? Date(),
                patientID:       "RM-005678",
                doctorName:      "dr. Hendra Wijaya",
                phone:           "0821-9876-5432",
                address:         "Jl. Sudirman No. 88, Bandung",
                examinationDate: Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date(),
                sampleType:      "Dahak",
                capturedFieldCount: 100,
                totalFieldCount: 100
            )
            s.analysisResult = AnalysisResult(
                btaCount: 0,
                confidence: 0.98,
                grade: .negative,
                analyzedAt: Date()
            )
            return s
        }(),
        Sample(
            patientName:     "Citra Lestari",
            accessionNumber: "ACC-2025-003",
            dateOfBirth:     Calendar.current.date(byAdding: .year, value: -28, to: Date()) ?? Date(),
            patientID:       "RM-009012",
            doctorName:      "dr. Maya Sari",
            phone:           "0838-1122-3344",
            address:         "Jl. Pahlawan No. 5, Surabaya",
            examinationDate: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date(),
            sampleType:      "Urine"
        )
    ]
}

// MARK: - SampleDraft preview fixture

extension SampleDraft {
    static var preview: SampleDraft {
        let d = SampleDraft()
        d.patientName     = "Ahmad Rizki"
        d.accessionNumber = "ACC-2025-001"
        d.dateOfBirth     = Calendar.current.date(byAdding: .year, value: -35, to: Date()) ?? Date()
        d.patientID       = "RM-001234"
        d.doctorName      = "dr. Sari Dewi"
        d.phone           = "0812-3456-7890"
        d.address         = "Jl. Merdeka No. 12, Jakarta"
        d.examinationDate = Date()
        d.sampleType      = "Dahak"
        d.notes           = "Batuk > 3 minggu"
        d.capturedFieldCount = 12
        d.manualBTACount     = 16
        d.aiConfidence       = 0.90
        d.grade              = .plus2
        return d
    }
}
