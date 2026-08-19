import Testing
import Foundation
@testable import Bacilab

/// Hasil analisis per lapang disimpan ke manifest JSON supaya sesi bisa dilanjutkan
/// setelah app ditutup. Round-trip harus utuh: box yang bergeser atau `failure` yang
/// hilang berarti angka di layar tidak lagi sama dengan yang tersimpan.
struct DetectionCodableTests {

    @Test("DetectorReading bolak-balik lewat JSON tanpa kehilangan apa pun")
    func readingRoundTrips() throws {
        let original = DetectorReading(
            detector: .yolo11,
            btaCount: 7,
            confidence: 0.82,
            elapsed: 1.25,
            boxes: [DetectedBox(cx: 0.5, cy: 0.25, w: 0.1, h: 0.05, angle: 0.7)],
            failure: nil
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DetectorReading.self, from: data)

        #expect(decoded == original)
    }

    @Test("Reading yang gagal tetap membawa pesan kegagalannya")
    func failureRoundTrips() throws {
        let original = DetectorReading(
            detector: .yolo11,
            btaCount: 0,
            confidence: 0,
            elapsed: 0.3,
            failure: "model tidak tersedia"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DetectorReading.self, from: data)

        #expect(decoded.failure == "model tidak tersedia")
        #expect(decoded.btaCount == 0)
    }

    @Test("BTAGrade bolak-balik lewat JSON")
    func gradeRoundTrips() throws {
        for grade in BTAGrade.allCases {
            let data = try JSONEncoder().encode(grade)
            #expect(try JSONDecoder().decode(BTAGrade.self, from: data) == grade)
        }
    }
}
