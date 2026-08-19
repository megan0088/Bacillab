import Testing
import SwiftUI
@testable import Bacilab

/// Tiga model digambar di atas lapang yang sama. Warna saja tidak cukup memisahkan tiga
/// kategori — pembaca buta warna dan tangkapan layar hitam-putih tetap harus bisa
/// membedakannya, jadi tiap model juga punya pola garis sendiri.
struct DetectorStyleTests {

    @Test("Setiap model punya warna berbeda")
    func tintsAreDistinct() {
        let tints = DetectorKind.allCases.map { DetectorStyle.tint(for: $0).description }
        #expect(Set(tints).count == DetectorKind.allCases.count)
    }

    @Test("Setiap model punya pola garis berbeda")
    func dashesAreDistinct() {
        let dashes = DetectorKind.allCases.map { DetectorStyle.dash(for: $0) }
        #expect(dashes[0] != dashes[1])
        #expect(dashes[1] != dashes[2])
        #expect(dashes[0] != dashes[2])
    }

    @Test("Pola garis ikut diperkecil bersama skalanya")
    func dashScales() {
        let full = DetectorStyle.dash(for: .yolo, scale: 1)
        let half = DetectorStyle.dash(for: .yolo, scale: 0.5)
        #expect(half == full.map { $0 * 0.5 })
    }

    /// Setiap model menomori kotaknya dari 0. Kalau id kotak hanya nomor itu, kotak ResNet
    /// nomor 3 dan kotak YOLO nomor 3 punya id yang sama, dan SwiftUI akan menggambar salah
    /// satunya di tempat yang lain.
    @Test("Id kotak tidak bertabrakan antar model")
    func markerIdentitiesAreUniqueAcrossModels() {
        let box = DetectedBox(cx: 0.5, cy: 0.5, w: 0.1, h: 0.05, angle: 0)
        let readings = DetectorKind.allCases.map { kind in
            DetectorReading(detector: kind, btaCount: 4, confidence: 0.8, elapsed: 0.1,
                            boxes: Array(repeating: box, count: 4))
        }

        let ids = FieldCanvas.markers(for: readings).map(\.id)

        #expect(ids.count == 12)
        #expect(Set(ids).count == 12, "Ada id kotak yang bertabrakan antar model")
    }

    @Test("Jumlah kotak yang digambar dibatasi per model")
    func boxesAreCappedPerModel() {
        let box = DetectedBox(cx: 0.5, cy: 0.5, w: 0.1, h: 0.05, angle: 0)
        let reading = DetectorReading(
            detector: .yolo, btaCount: 500, confidence: 0.8, elapsed: 0.1,
            boxes: Array(repeating: box, count: 500)
        )

        #expect(FieldCanvas.markers(for: [reading]).count == FieldCanvas.boxDisplayLimit)
    }
}
