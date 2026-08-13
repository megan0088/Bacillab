import CoreGraphics
import UIKit

/// Seberapa tajam sebuah frame, tanpa menjalankan model apa pun.
///
/// Peringatan fokus harus jalan tiap frame, jadi ia tidak boleh menyentuh detektor — satu
/// lapang ResNet butuh hitungan detik. Yang dipakai di sini rata-rata kuadrat selisih piksel
/// bertetangga: gambar tajam punya banyak tepi tajam, gambar buram tidak.
enum FocusMetric {

    /// Sisi gambar kerja. Cukup kecil untuk berjalan tiap frame, cukup besar untuk
    /// mempertahankan tepi yang jadi kabur ketika fokus meleset.
    private static let workingSide = 128

    /// Di bawah ini frame dianggap buram.
    ///
    /// **Belum dikalibrasi.** Angka ini berasal dari gambar sintetis, bukan dari preparat
    /// sungguhan di bawah okuler. Sampai diukur dengan slide asli, peringatannya hanya boleh
    /// memberi saran — jangan pernah dipakai memblokir capture.
    static let blurThreshold: Double = 0.0015

    static func isBlurry(_ sharpness: Double) -> Bool {
        sharpness < blurThreshold
    }

    static func sharpness(of image: UIImage) -> Double {
        guard let cgImage = image.cgImage else { return 0 }
        return sharpness(of: cgImage)
    }

    static func sharpness(of image: CGImage) -> Double {
        let side = workingSide
        var pixels = [UInt8](repeating: 0, count: side * side)

        guard let context = CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return 0 }

        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))

        // Rata-rata kuadrat gradien, horizontal dan vertikal. Dinormalisasi ke [0, 1] supaya
        // ambangnya tidak bergantung pada kedalaman bit.
        var total = 0.0
        var samples = 0
        for y in 0..<(side - 1) {
            for x in 0..<(side - 1) {
                let i = y * side + x
                let dx = Double(pixels[i + 1]) - Double(pixels[i])
                let dy = Double(pixels[i + side]) - Double(pixels[i])
                total += (dx * dx + dy * dy) / (255.0 * 255.0)
                samples += 1
            }
        }

        guard samples > 0 else { return 0 }
        return total / Double(samples)
    }
}
