import Foundation

struct AnalysisResult: Hashable, Sendable {
    let btaCount: Int
    let confidence: Double
    let grade: BTAGrade
    let analyzedAt: Date
}

enum BTAGrade: String, Hashable, CaseIterable, Sendable {
    case negative = "Negatif"
    case scanty   = "Scanty"
    case plus1    = "1+"
    case plus2    = "2+"
    case plus3    = "3+"

    /// Fields that must be read before this grade may be reported as final.
    ///
    /// WHO/IUATLD scales the workload to the density: a heavy smear declares itself
    /// quickly, while calling a slide Negatif or Scanty demands the full 100 fields —
    /// that is the reading which, if wrong, sends an infectious patient home untreated.
    var minimumFields: Int {
        switch self {
        case .plus3:                       return 20
        case .plus2:                       return 50
        case .plus1, .scanty, .negative:   return 100
        }
    }

    // IUATLD grading: totalBTA across all scanned fields, extrapolated to per-100-field scale
    static func grade(for totalBTA: Int, across fields: Int) -> BTAGrade {
        guard fields > 0, totalBTA > 0 else { return .negative }
        let per100 = Double(totalBTA) / Double(fields) * 100
        switch per100 {
        case ..<1:       return .negative
        case 1..<10:     return .scanty
        case 10..<100:   return .plus1
        case 100...1000: return .plus2
        default:         return .plus3
        }
    }
}
