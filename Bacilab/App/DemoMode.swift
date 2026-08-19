import Foundation

/// Switches that exist for the exhibition build, and nowhere else.
///
/// Each flag here suppresses something that is in the app for a reason, so each one states what
/// it costs. They are compile-time constants rather than settings: a demo switch that a user can
/// reach is a demo switch that can be left on in a clinic.
enum DemoMode {

    /// Hides the PROVISIONAL marks — the chip on the result sheet, the `· Provisional` suffix in
    /// history, and the shortfall warning in Review.
    ///
    /// **This hides the marks, not the gate.** `BTAGrade.minimumFields` and
    /// `ExamSession.isGradeConfirmed` are untouched and still compute exactly as before; only the
    /// three places that draw the result stay quiet. `Continue Scanning` also stays, so the way to
    /// actually reach a confirmed grade is still there.
    ///
    /// What it costs, plainly: with this on, a Negative read from 20 fields is indistinguishable
    /// on screen from a Negative read from the full 100 that WHO/IUATLD require — and that is the
    /// reading which, if wrong, sends an infectious patient home untreated. It is acceptable here
    /// only because the seeded demo session is 50 fields and genuinely reaches a confirmed 2+, so
    /// nothing is being concealed in what the demo actually shows.
    ///
    /// **Set this to `false` before the app is used on a real slide.**
    static let hidesProvisionalMarks = true
}
