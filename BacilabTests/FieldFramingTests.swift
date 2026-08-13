import Testing
import Foundation
import UIKit
@testable import Bacilab

/// Berkas lapang adalah satu-satunya salinan yang dilihat model, karena analisis berjalan
/// setelah scan selesai. Ukurannya karena itu terikat pada transform model, bukan pada
/// kenyamanan tampilan.
struct FieldFramingTests {

    private func image(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
            .image { ctx in
                UIColor.blue.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
                UIColor.magenta.setFill()
                ctx.fill(CGRect(x: width / 3, y: height / 3, width: 40, height: 12))
            }
    }

    @Test("Foto besar dipotong persegi dan dikecilkan ke 1600 px")
    func largePhotoIsCappedAt1600() throws {
        let data = try #require(FieldFraming.analysisJPEG(of: image(width: 3024, height: 4032)))
        let decoded = try #require(UIImage(data: data))

        #expect(decoded.size.width == decoded.size.height, "Harus persegi")
        #expect(decoded.size.width == 1600,
                "Di atas 1600 px tidak menambah apa pun yang dilihat model (max_size=1600)")
    }

    @Test("Gambar kecil tidak diperbesar")
    func smallPhotoIsNotUpscaled() throws {
        let data = try #require(FieldFraming.analysisJPEG(of: image(width: 800, height: 600)))
        let decoded = try #require(UIImage(data: data))

        #expect(decoded.size.width == 600, "Sisi persegi mengikuti sisi terpendek")
        #expect(decoded.size.height == 600)
    }

    @Test("Hasilnya JPEG yang bisa dibaca ulang")
    func outputIsDecodable() throws {
        let data = try #require(FieldFraming.analysisJPEG(of: image(width: 2000, height: 2000)))

        #expect(!data.isEmpty)
        #expect(UIImage(data: data) != nil)
    }
}
