import SwiftUI

/// Satu warna dan satu pola garis per model, dipakai baik oleh box di atas gambar maupun
/// oleh angka di bawahnya — supaya analis tidak perlu menebak box mana milik angka mana.
///
/// Pola garis bukan hiasan: warna saja tidak bisa memisahkan tiga kategori untuk pembaca
/// buta warna, dan tangkapan layar hitam-putih sering jadi satu-satunya yang tersisa ketika
/// sebuah hasil dipertanyakan.
enum DetectorStyle {

    static func tint(for detector: DetectorKind) -> Color {
        switch detector {
        case .resnet: return .red
        case .yolo:   return .cyan
        case .yolo11: return .yellow
        }
    }

    static func dash(for detector: DetectorKind, scale: CGFloat = 1) -> [CGFloat] {
        switch detector {
        case .resnet: return []
        case .yolo:   return [4 * scale, 3 * scale]
        case .yolo11: return [1.5 * scale, 2.5 * scale]
        }
    }
}
