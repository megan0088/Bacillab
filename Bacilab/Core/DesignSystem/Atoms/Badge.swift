import SwiftUI

/// A pill carrying a short status or grade, tinted by severity.
///
/// The background is the tint at low opacity rather than a separate colour, so a new tint needs
/// one decision instead of two that can drift apart.
struct Badge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.appCaption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }
}

#Preview("Badge") {
    VStack(spacing: 8) {
        Badge(text: "Positive 3+", tint: BTAGrade.plus3.tint)
        Badge(text: "Negative", tint: BTAGrade.negative.tint)
        Badge(text: "In progress", tint: .orange)
    }
    .padding()
}
