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

        // The context is created, drawn into, and read entirely inside this closure.
        //
        // Passing `&pixels` straight to `CGContext(data:)` hands it a pointer that is only
        // guaranteed valid for the duration of that one call, while the context holds it for its
        // whole lifetime and `draw` writes through it afterwards. That is undefined behaviour —
        // it merely tends to look correct because the array's storage happens not to move, and
        // it is exactly the shape Xcode's Exclusive Access to Memory checking traps at runtime.
        return pixels.withUnsafeMutableBytes { raw -> Double in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                      data: base,
                      width: side,
                      height: side,
                      bitsPerComponent: 8,
                      bytesPerRow: side,
                      space: CGColorSpaceCreateDeviceGray(),
                      bitmapInfo: CGImageAlphaInfo.none.rawValue
                  )
            else { return 0 }

            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))

            // Mean squared gradient, horizontal and vertical, normalised to [0, 1] so the
            // threshold does not depend on bit depth.
            let bytes = raw.bindMemory(to: UInt8.self)
            var total = 0.0
            var samples = 0
            for y in 0..<(side - 1) {
                for x in 0..<(side - 1) {
                    let i = y * side + x
                    let dx = Double(bytes[i + 1]) - Double(bytes[i])
                    let dy = Double(bytes[i + side]) - Double(bytes[i])
                    total += (dx * dx + dy * dy) / (255.0 * 255.0)
                    samples += 1
                }
            }

            guard samples > 0 else { return 0 }
            return total / Double(samples)
        }
    }
}
