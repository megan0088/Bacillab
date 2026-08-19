import SwiftUI

/// The one place a grade's colour is decided.
///
/// It used to be decided twice — one switch in the history list, another in the result sheet —
/// and the two drifted: 1+ was moved to orange on the card while the sheet still returned red,
/// so a single slide showed in two colours depending on which screen you were looking at.
/// Colour is how severity reads at a glance here, so that disagreement is not cosmetic.
///
/// Scanty and 1+ deliberately share orange: both are positive findings short of a heavy smear.
/// They are not clinically identical — Scanty calls for a repeat examination — but the label
/// beside the colour says which is which, and splitting them would need a fifth hue that means
/// nothing on its own.
extension BTAGrade {
    var tint: Color {
        switch self {
        case .negative:       return .green
        case .scanty, .plus1: return .orange
        case .plus2, .plus3:  return .red
        }
    }
}
