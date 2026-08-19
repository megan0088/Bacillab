import SwiftUI

/// A section title. `tinted` marks the accent-coloured headings the result sheet and the patient
/// form use to open a group; plain is for headings inside one.
///
/// Two screens had each grown their own version of this, one called `sectionHeading` and one
/// `sectionHeader`, differing only in whether the tint was a parameter.
struct SectionHeader: View {
    let title: String
    var tinted: Bool = false

    init(_ title: String, tinted: Bool = false) {
        self.title = title
        self.tinted = tinted
    }

    var body: some View {
        Text(title)
            .font(.appBody.weight(.bold))
            .foregroundStyle(tinted ? Color.accentColor : .primary)
    }
}

#Preview("SectionHeader") {
    VStack(alignment: .leading, spacing: 12) {
        SectionHeader("Patient Information", tinted: true)
        SectionHeader("Total Fields Read")
    }
    .padding()
}
