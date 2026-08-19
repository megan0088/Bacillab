import SwiftUI

/// The first screen, held for a beat while the history loads and the demo seed is written.
///
/// The artwork is a single composed image from the design file — photograph, wordmark and
/// standards note already baked in — so nothing here is laid out in SwiftUI. That makes it
/// fixed at 804×1748: it fills any modern iPhone (0.46 aspect, which is what these are) but a
/// noticeably wider screen crops the edges of the photograph rather than reflowing. Replacing
/// the flat image with a live layout is the fix if this ever has to hold up on iPad.
struct SplashView: View {
    var body: some View {
        Image("Splash")
            .resizable()
            .scaledToFill()
            .ignoresSafeArea()
            .accessibilityLabel(
                "NexScoupe. Faster counts, better care. Based on the standardized reporting "
                + "guidelines of WHO and IUATLD for Ziehl–Neelsen sputum smear microscopy."
            )
    }
}

#Preview("Splash") {
    SplashView()
}
