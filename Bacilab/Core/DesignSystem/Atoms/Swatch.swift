import SwiftUI

/// A short line drawn in a tint and dash pattern, used to name what a pattern means.
///
/// It repeats the stroke rather than showing a plain colour chip on purpose: a chip would be
/// indistinguishable in a black-and-white screenshot and for a colour-blind reader, which is the
/// same reason the patterns exist on the boxes it is explaining.
struct Swatch: View {
    let tint: Color
    var dash: [CGFloat] = []

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 5))
            path.addLine(to: CGPoint(x: 26, y: 5))
        }
        .stroke(tint, style: StrokeStyle(lineWidth: 2.5, dash: dash))
        .frame(width: 26, height: 10)
    }
}

#Preview("Swatch") {
    VStack(alignment: .leading, spacing: 8) {
        Swatch(tint: .red)
        Swatch(tint: .yellow, dash: [1.5, 2.5])
    }
    .padding()
    .background(.black)
}
