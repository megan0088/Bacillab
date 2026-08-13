import Testing
import Foundation
import UIKit
@testable import Bacilab

/// Peringatan fokus berjalan tiap frame, jadi ia harus murah dan tidak melibatkan model.
/// Yang diuji di sini sifat urutannya — gambar tajam harus selalu menilai lebih tinggi
/// daripada gambar rata — bukan angka mutlaknya, yang memang belum dikalibrasi.
struct FocusMetricTests {

    private func checkerboard(size: CGFloat = 256, cell: CGFloat = 8) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
            .image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
                UIColor.black.setFill()
                var row = 0
                var y: CGFloat = 0
                while y < size {
                    var x: CGFloat = (row % 2 == 0) ? 0 : cell
                    while x < size {
                        ctx.fill(CGRect(x: x, y: y, width: cell, height: cell))
                        x += cell * 2
                    }
                    y += cell
                    row += 1
                }
            }
    }

    private func flat(size: CGFloat = 256) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
            .image { ctx in
                UIColor.gray.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            }
    }

    @Test("Gambar bertepi tajam menilai lebih tinggi daripada gambar rata")
    func sharpScoresHigherThanFlat() {
        let sharp = FocusMetric.sharpness(of: checkerboard())
        let blurry = FocusMetric.sharpness(of: flat())

        #expect(sharp > blurry)
        #expect(blurry >= 0, "Ketajaman tidak pernah negatif")
    }

    @Test("Bidang rata dinilai buram")
    func flatFieldIsBlurry() {
        #expect(FocusMetric.isBlurry(FocusMetric.sharpness(of: flat())))
    }

    @Test("Bidang bertepi tajam tidak dinilai buram")
    func sharpFieldIsNotBlurry() {
        #expect(!FocusMetric.isBlurry(FocusMetric.sharpness(of: checkerboard())))
    }

    @Test("Petak lebih halus menilai lebih tinggi daripada petak lebih kasar")
    func finerDetailScoresHigher() {
        let fine = FocusMetric.sharpness(of: checkerboard(cell: 4))
        let coarse = FocusMetric.sharpness(of: checkerboard(cell: 32))

        #expect(fine > coarse, "Detail halus adalah yang pertama hilang saat fokus meleset")
    }
}
