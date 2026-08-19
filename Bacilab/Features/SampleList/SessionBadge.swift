import SwiftUI

/// What a history row's badge says about a session, and in what colour.
///
/// Separated from the view because this is a clinical decision, not styling: it decides whether a
/// grade may appear as a conclusion. Below the WHO/IUATLD field minimum it is not one, and the
/// list is where people scan to see what a slide said — so it must not read as final while the
/// result sheet marks the same session provisional.
///
/// The sharpest case is a session whose fields all failed analysis: nothing was read,
/// `suggestedGrade` falls back to Negative, and without the confirmation check the row would show
/// a plain green "Negative" for a slide nobody looked at.
struct SessionBadge {
    let text: String
    let tint: Color

    init(session: ExamSession) {
        guard session.status == .published else {
            text = "In progress"
            tint = .orange
            return
        }

        let name = session.reportedGrade.displayName

        guard session.isGradeConfirmed || DemoMode.hidesProvisionalMarks else {
            text = "\(name) · Provisional"
            tint = .orange
            return
        }

        text = name
        tint = session.reportedGrade.tint
    }
}
