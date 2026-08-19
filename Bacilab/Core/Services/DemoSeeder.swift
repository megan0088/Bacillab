import Foundation
import UIKit

private let seedLog = Diag("seed")

/// Fills an empty history with one demo examination so the app has something to show.
///
/// **It seeds images, never readings.** The source tiles ship with ground-truth annotations, and
/// planting those counts would make the session look instantly analysed — but the numbers on
/// screen would be ones no model produced. Everything shown next to a grade has to be the
/// detector's own output, so the seeded fields arrive unanalysed and the real models count them.
///
/// The fields are the 20 densest slides in `tuberculosis-phonecamera`, chosen by the lab from
/// their own ranking (`top-20-BTA-terbanyak`). Measured through the app's own framing and
/// circular field of view, the models find **307 bacilli across 20 fields — 1535 per 100**, which
/// is 3+, and 3+ is the one grade WHO/IUATLD confirm at 20 fields. So the demo reaches a final
/// grade in a single batch.
///
/// **This is the model's best possible showing, and the gap is wide.** 17 of these 20 images are
/// in fold 4's *training* split: the model memorised them. They are also the densest slides in the
/// set, where detection is easiest. Real performance is `calibrated_metrics.json` — precision
/// 0.79, recall 0.76, count MAE 1.32 — on held-out images, and none of it has been checked against
/// slides read at Electra Lab. Do not quote the demo as accuracy.
///
/// They are **not** the 416 px tiles in `AI TBC/output/TestingData`, which this file used until
/// 2026-08-19. Those are cut for the YOLO pipeline, and this ResNet finds **zero** bacilli in them
/// at every scale — verified against the ONNX graph, including on untouched source files. The demo
/// therefore graded every seeded slide Negative while appearing to work. Any future change of image
/// source must be checked by counting what the model actually detects: this failure is silent.
enum DemoSeeder {

    /// Matches the bundled `demo-field-NNN.jpg` files.
    static let fieldCount = 20

    /// Seeds one session if — and only if — there is no history at all.
    ///
    /// Guarded on emptiness rather than a flag so it can never bury real work: the moment a
    /// technician saves anything, seeding stops happening.
    static func seedIfEmpty(store: any SessionStoreProtocol) async {
        do {
            guard try await store.allSessions().isEmpty else { return }
            try await seed(into: store)
        } catch {
            // A demo that fails to seed is a cosmetic problem; it must never stop the app from
            // opening, so this is logged and swallowed rather than surfaced.
            seedLog.error("Seeding demo data failed: \(error.localizedDescription)")
        }
    }

    /// Five sessions, so the history looks like a working day rather than a single record.
    ///
    /// **Each one gets all 20 fields, and that is forced by the grading rules, not a shortcut.**
    /// 3+ is the only grade WHO/IUATLD confirm at 20 fields — 2+ needs 50, everything else needs
    /// 100 — so a session seeded with a smaller subset could never reach a final grade, and with
    /// the provisional marks hidden for the exhibition it would show a shortfall grade looking
    /// exactly like a conclusion. With 20 source images and five sessions, the images therefore
    /// repeat; what differs is the patient, the date, and the order the fields were read in.
    private static func seed(into store: any SessionStoreProtocol) async throws {
        for (offset, patient) in demoPatients.enumerated() {
            let session = ExamSession(patient: patient, status: .reviewing)

            // A different reading order per session: a slide is read field by field in whatever
            // order the stage moves, and identical ordering across five patients would be the
            // one detail that gives the seeding away at a glance.
            var order = Array(0..<fieldCount)
            order.shuffle()

            for sourceIndex in order {
                let name = String(format: "demo-field-%03d", sourceIndex)
                guard let url = Bundle.main.url(forResource: name, withExtension: "jpg"),
                      let raw = try? Data(contentsOf: url),
                      let image = UIImage(data: raw),
                      // Framed exactly as a captured field would be, so the demo exercises the
                      // same pixels the detectors see in real use.
                      let jpeg = FieldFraming.analysisJPEG(of: image)
                else {
                    seedLog.error("Demo field \(name) missing from the bundle")
                    continue
                }

                let fileName = String(format: "field-%03d.jpg", session.fields.count)
                try store.writeFieldImage(jpeg, fileName: fileName, for: session)
                // Tagged `.gallery`: these fields did not come through an eyepiece, and the
                // result sheet counts imported fields separately for exactly that reason.
                session.appendField(imageFileName: fileName, source: .gallery)
            }

            guard !session.fields.isEmpty else {
                seedLog.error("No demo fields were bundled; nothing seeded")
                return
            }

            try await store.save(session.snapshot())
            seedLog.note("Seeded demo session \(offset + 1) of \(demoPatients.count) "
                         + "with \(session.fields.count) fields, unanalysed")
        }
    }

    /// Obviously fictional, so nobody mistakes the demo for a patient record.
    ///
    /// The `DEMO —` prefix is the guard: these sit in the same history as real examinations, and
    /// a plausible-looking name beside a 3+ result is a record someone could act on.
    private static var demoPatients: [PatientInfo] {
        let people: [(String, String, String)] = [
            ("DEMO — Charles Game",   "RM 240724-001", "3204010101900001"),
            ("DEMO — Ratna Kusuma",   "RM 240724-002", "3204010101900002"),
            ("DEMO — Bagus Prayoga",  "RM 240724-003", "3204010101900003"),
            ("DEMO — Siti Halimah",   "RM 240724-004", "3204010101900004"),
            ("DEMO — Yusuf Ardiansyah", "RM 240724-005", "3204010101900005"),
        ]

        return people.enumerated().map { index, person in
            var patient = PatientInfo()
            patient.name = person.0
            patient.medicalRecordNumber = person.1
            patient.nationalID = person.2
            patient.address = "Demo data — not a real record"
            patient.phone = "—"
            patient.dateOfBirth = Calendar.current.date(
                from: DateComponents(year: 1985 + index * 2, month: 1 + index, day: 1 + index)) ?? Date()
            // Staggered so the history sorts into a sequence instead of five identical rows.
            patient.examinationDate = Calendar.current.date(
                byAdding: .day, value: -index, to: Date()) ?? Date()
            return patient
        }
    }
}
