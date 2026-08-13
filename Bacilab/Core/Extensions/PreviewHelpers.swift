import Foundation

extension ExamSession {

    /// Sesi 20 lapang padat — 3+ dan sudah memenuhi ambangnya.
    static var previewHeavy: ExamSession {
        make(name: "Ahmad Rizki", mrn: "RM 240724-001",
             counts: Array(repeating: 15, count: 20), status: .published)
    }

    /// Sesi 20 lapang bersih — Negatif, tapi masih jauh dari 100 lapang yang disyaratkan.
    static var previewNegative: ExamSession {
        make(name: "Siti Rahma", mrn: "RM 240724-002",
             counts: Array(repeating: 0, count: 20), status: .published)
    }

    /// Sesi yang ditinggal di tengah scan.
    static var previewRunning: ExamSession {
        make(name: "Budi Santoso", mrn: "RM 240724-003",
             counts: [2, 0, 1, 0, 3], status: .scanning)
    }

    private static func make(
        name: String,
        mrn: String,
        counts: [Int],
        status: SessionStatus
    ) -> ExamSession {
        let session = ExamSession()
        session.patient.name = name
        session.patient.medicalRecordNumber = mrn
        session.status = status
        for count in counts {
            let field = session.appendField(imageFileName: "field.jpg")
            session.setAnalysis(
                FieldAnalysis(
                    readings: [DetectorReading(detector: .resnet, btaCount: count,
                                               confidence: 0.86, elapsed: 0.6)],
                    primary: .resnet
                ),
                for: field.id
            )
        }
        return session
    }
}
