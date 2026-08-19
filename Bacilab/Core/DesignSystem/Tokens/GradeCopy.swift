import Foundation

/// The words used for a grade, in one place.
///
/// This exists because `BTAGrade.rawValue` cannot be the display name: it is the key each grade
/// is stored under in `manifest.json`, so changing it to read better on screen would make every
/// saved session fail to decode — and `SessionStore` skips manifests it cannot read, so those
/// sessions disappear from the list rather than raising anything.
///
/// Before this, three screens each solved that privately and disagreed: the result sheet said
/// "Positive (1+)", the history said "Positive 1+", and Review printed the raw "1+". One slide,
/// three names, depending on where you looked.
extension BTAGrade {

    /// The grade as a reader should see it. Never render `rawValue` in the UI.
    var displayName: String {
        switch self {
        case .negative: return "Negative"
        case .scanty:   return "Scanty"
        case .plus1:    return "Positive 1+"
        case .plus2:    return "Positive 2+"
        case .plus3:    return "Positive 3+"
        }
    }

    /// The WHO/IUATLD definition of the band — a definition, not a report of what was seen.
    ///
    /// Negative and Scanty name the full 100 fields on purpose: that is the number which decides
    /// whether the reading may be reported at all, and it is the figure someone needs in front of
    /// them at the moment they decide.
    var criterion: String {
        switch self {
        case .negative: return "No BTA in 100 fields of view"
        case .scanty:   return "1–9 BTA in 100 fields of view; repeat examination advised"
        case .plus1:    return "10–99 BTA in 100 fields of view"
        case .plus2:    return "1–10 BTA per field, across at least 50 fields"
        case .plus3:    return "More than 10 BTA per field, across at least 20 fields"
        }
    }
}
