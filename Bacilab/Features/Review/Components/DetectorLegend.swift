import SwiftUI

/// Names the models drawing on the field, beside the count each one reached.
///
/// The canvas flattens every model's boxes into one overlay, distinguished only by colour and
/// dash pattern. Without this, which model drew a box — and which one the grade came from — is
/// something the analyst has to already know. That matters most when the models disagree, which
/// is exactly when someone looks closely.
///
/// The swatch repeats `DetectorStyle`'s dash pattern rather than showing a plain colour chip, so
/// it stays readable in a black-and-white screenshot and for a colour-blind reader — the same
/// reason the patterns exist on the boxes.
struct DetectorLegend: View {
    let readings: [DetectorReading]
    let primary: DetectorKind

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(readings, id: \.detector) { reading in
                HStack(spacing: 8) {
                    swatch(for: reading.detector)

                    Text(reading.detector.rawValue)
                        .font(.appCaption.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(reading.failure == nil ? "\(reading.btaCount) BTA" : "did not run")
                        .font(.appCaption)
                        .foregroundStyle(.white.opacity(0.7))

                    Spacer(minLength: 8)

                    // Only one model's number ever becomes the result; the rest ride along. A
                    // reader with three counts in front of them cannot tell which is which.
                    Text(reading.detector == primary ? "grades this slide" : "comparison only")
                        .font(.appCaption)
                        .foregroundStyle(reading.detector == primary
                                         ? .white.opacity(0.85) : .white.opacity(0.45))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private func swatch(for detector: DetectorKind) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 5))
            path.addLine(to: CGPoint(x: 26, y: 5))
        }
        .stroke(DetectorStyle.tint(for: detector),
                style: StrokeStyle(lineWidth: 2.5, dash: DetectorStyle.dash(for: detector)))
        .frame(width: 26, height: 10)
    }
}

#Preview("Legend") {
    DetectorLegend(
        readings: [
            DetectorReading(detector: .resnet, btaCount: 21, confidence: 0.86, elapsed: 2.1),
            DetectorReading(detector: .yolo11, btaCount: 15, confidence: 0.49, elapsed: 0.2),
        ],
        primary: .resnet
    )
    .padding()
    .background(.black)
}
