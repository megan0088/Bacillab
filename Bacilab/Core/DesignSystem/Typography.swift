import SwiftUI

/// The only four type sizes this app uses: **34 / 22 / 17 / 13**, all SF Pro.
///
/// SF Pro is the system face, so these are `Font.system(size:)` with the default design —
/// deliberately *not* `.rounded`, which is SF Pro Rounded and a different typeface.
///
/// Apply weight at the call site rather than adding sizes: `.appBody.weight(.semibold)`.
/// If a piece of text seems to need a fifth size, it almost always needs a different weight or
/// a different colour instead.
///
/// **These sizes are fixed and do not respond to Dynamic Type.** That is the cost of a strict
/// scale: someone who has enlarged system text will not see this app grow with it, and 13pt is
/// small for a lab bench. Worth revisiting with `@ScaledMetric` if the clinic asks.
extension Font {
    /// 34 — screen titles.
    static let appTitle = Font.system(size: 34, weight: .bold)

    /// 22 — section headings and the numbers that carry a screen.
    static let appHeading = Font.system(size: 22, weight: .bold)

    /// 17 — body copy, labels, buttons.
    static let appBody = Font.system(size: 17)

    /// 13 — captions, criteria, secondary detail.
    static let appCaption = Font.system(size: 13)
}
