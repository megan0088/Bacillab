import CoreGraphics
import UIKit

/// How a captured photo becomes the pixels a detector sees.
///
/// This lives on its own for one reason: **both** detectors must be handed byte-identical
/// input. `DualDetectorService` compares their counts on the same field, and if the two
/// framed the photo even slightly differently the difference in counts would be part
/// framing and part model, with no way to tell which. One function, one framing, so any
/// disagreement is genuinely about the models.
enum FieldFraming {

    /// Redraws the photo upright and crops it to the largest centred square.
    ///
    /// A photo straight out of `AVCapturePhotoOutput` carries its rotation in EXIF, which a
    /// bare `CGImage` drops — the field would be analysed sideways. `draw` applies
    /// `imageOrientation`, so what lands in the context is upright.
    ///
    /// The square crop keeps the overlay honest: `CaptureView` draws detections into the
    /// circular microscope viewport as a square, so boxes have to be normalised against a
    /// square. It suits both models. YOLO letterboxes into 1024×1024, where a 4:3 frame
    /// would shrink bacilli below the ~13 px it was trained at. Faster R-CNN resizes to min
    /// side 1200, which a 4:3 frame and its square crop both hit on the short side, so the
    /// crop costs nothing there either.
    static func uprightCenteredSquare(of image: UIImage) -> CGImage? {
        let side = min(image.size.width, image.size.height)
        guard side > 0 else { return nil }

        let origin = CGPoint(
            x: (image.size.width - side) / 2,
            y: (image.size.height - side) / 2
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: side, height: side),
            format: format
        )
        let square = renderer.image { _ in
            image.draw(at: CGPoint(x: -origin.x, y: -origin.y))
        }
        return square.cgImage
    }

    /// Sisi maksimum berkas lapang yang disimpan.
    ///
    /// Transform Faster R-CNN memakai `min_size=1200, max_size=1600`, jadi apa pun di atas
    /// 1600 px akan dikecilkan lagi oleh model sendiri. Menyimpan lebih besar hanya memakan
    /// disk — dan sesi 20 lapang sudah puluhan megabita.
    static let maxAnalysisSide: CGFloat = 1600

    /// Berkas lapang siap-analisis: tegak, persegi, dan tidak lebih besar dari yang dipakai model.
    ///
    /// Analisis berjalan belakangan dari berkas ini, jadi ia harus berisi piksel yang sama
    /// dengan yang akan dilihat detektor. Thumbnail tidak cukup.
    static func analysisJPEG(of image: UIImage) -> Data? {
        guard let square = uprightCenteredSquare(of: image) else { return nil }

        let sourceSide = CGFloat(square.width)
        // Tidak pernah memperbesar: menaikkan resolusi tidak menambah informasi apa pun.
        let side = min(sourceSide, maxAnalysisSide)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(
            size: CGSize(width: side, height: side),
            format: format
        ).image { _ in
            UIImage(cgImage: square).draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }

        return resized.jpegData(compressionQuality: 0.9)
    }
}
