import SwiftUI

/// A bordered text field whose name lives in the placeholder, matching the hi-fi.
struct LabeledField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .padding(14)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
    }
}

/// The same row for a date. A date picker has no placeholder to carry its name, so the name stays
/// a leading label — which is also how the hi-fi draws these.
struct LabeledDateField: View {
    let label: String
    @Binding var date: Date
    var components: DatePickerComponents = .date

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            DatePicker("", selection: $date, displayedComponents: components)
                .labelsHidden()
        }
        .padding(14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }
}

#Preview("LabeledField") {
    @Previewable @State var text = ""
    @Previewable @State var date = Date()
    return VStack(spacing: 12) {
        LabeledField(placeholder: "Patient Name", text: $text)
        LabeledDateField(label: "Date of Birth", date: $date)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
