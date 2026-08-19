import SwiftUI

/// The rounded surface every screen groups related content in.
///
/// Extracted because the same background was written out in six feature files, which is how two
/// cards end up with different corner radii on adjacent screens without anyone deciding that.
///
/// The defaults are the shape the result sheet already used; `spacing` is exposed because the
/// review screen packs its rows tighter, and that is a layout choice rather than a different
/// kind of surface.
struct Card<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview("Card") {
    Card {
        Text("Result").font(.appBody.weight(.bold))
        Text("Positive 2+").font(.appTitle)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
