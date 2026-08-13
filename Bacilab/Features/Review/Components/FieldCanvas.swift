import SwiftUI

/// Gambar satu lapang dengan box tiap model di atasnya.
///
/// Gambar yang ditampilkan adalah crop persegi yang persis diterima model, jadi koordinat box
/// yang ternormalisasi jatuh tepat di tempatnya. Menggambar box di atas gambar lain — foto
/// mentah, atau preview langsung — akan menempatkannya di atas basil yang bukan itu.
///
/// Bingkainya **kotak**, dengan lingkaran putus-putus sebagai panduan okuler. Masker lingkaran
/// akan menyembunyikan sudut-sudutnya, sekitar 21% dari luas yang tetap dibaca model.
struct FieldCanvas: View {
    let image: UIImage?
    let readings: [DetectorReading]
    let side: CGFloat

    /// Satu box siap gambar, ditandai model asalnya.
    ///
    /// Semua model diratakan ke satu daftar dengan id eksplisit. `ForEach` bersarang —
    /// satu per bacaan, satu per box di dalamnya — membuat id lapisan dalam (`0, 1, 2…`)
    /// berulang untuk tiap model, dan SwiftUI akan menggambar kotak yang salah.
    struct Marker: Identifiable {
        let id: String
        let detector: DetectorKind
        let box: DetectedBox
    }

    /// Berapa banyak box per model yang digambar.
    ///
    /// Batas tampilan murni supaya lapang yang sangat padat tidak menaruh ribuan bentuk di
    /// layar. **Tidak pernah menyentuh hitungan** — angka BTA tetap dari model, bukan dari
    /// berapa kotak yang sempat digambar.
    static let boxDisplayLimit = 120

    /// Dibuat sebagai fungsi statis, bukan properti privat, supaya invarian id-nya bisa diuji
    /// tanpa merender view.
    static func markers(for readings: [DetectorReading]) -> [Marker] {
        readings.flatMap { reading in
            reading.boxes.prefix(boxDisplayLimit).enumerated().map { index, box in
                Marker(id: "\(reading.detector.rawValue)-\(index)",
                       detector: reading.detector, box: box)
            }
        }
    }

    private var markers: [Marker] { Self.markers(for: readings) }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .overlay {
                        ProgressView()
                    }
            }

            ForEach(markers) { marker in
                Rectangle()
                    .stroke(
                        DetectorStyle.tint(for: marker.detector),
                        style: StrokeStyle(lineWidth: 2,
                                           dash: DetectorStyle.dash(for: marker.detector))
                    )
                    .frame(
                        width: max(CGFloat(marker.box.w) * side, 8),
                        height: max(CGFloat(marker.box.h) * side, 8)
                    )
                    .rotationEffect(.radians(Double(marker.box.angle)))
                    .offset(
                        x: CGFloat(marker.box.cx - 0.5) * side,
                        y: CGFloat(marker.box.cy - 0.5) * side
                    )
            }

            Circle()
                .stroke(.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                .padding(2)
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.systemGray3), lineWidth: 1))
    }
}

#Preview("Field canvas") {
    FieldCanvas(
        image: nil,
        readings: [
            DetectorReading(detector: .resnet, btaCount: 2, confidence: 0.9, elapsed: 0.6,
                            boxes: [DetectedBox(cx: 0.35, cy: 0.4, w: 0.08, h: 0.03, angle: 0.5),
                                    DetectedBox(cx: 0.6, cy: 0.65, w: 0.07, h: 0.03, angle: -0.3)])
        ],
        side: 300
    )
    .padding()
}
