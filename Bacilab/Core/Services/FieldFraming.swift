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
}
