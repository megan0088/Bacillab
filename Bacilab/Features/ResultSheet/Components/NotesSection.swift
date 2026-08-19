import SwiftUI

/// Lab notes on the result sheet — the one field this screen lets the lab edit outright.
///
/// A comment is often added after a result has been read, and it is not part of the reading
/// itself, unlike the grade and the counts, which were all decided in Review.
struct NotesSection: View {
    @Bindable var session: ExamSession

    var body: some View {
        Card {
            SectionHeader("Notes by Medical Laboratory", tinted: false)

            TextEditor(text: $session.notes)
                .frame(minHeight: 90)
                .scrollContentBackground(.hidden)
                .padding(8)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray4), lineWidth: 1))
                .overlay(alignment: .topLeading) {
                    if session.notes.isEmpty {
                        Text("Enter notes (optional)...")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 16)
                            .padding(.leading, 13)
                            .allowsHitTesting(false)
                    }
                }
        }
    }
}

#Preview("Notes") {
    let session = ExamSession()
    session.notes = "Sputum sample, morning collection."
    return NotesSection(session: session)
        .padding()
        .background(Color(.systemGroupedBackground))
}
