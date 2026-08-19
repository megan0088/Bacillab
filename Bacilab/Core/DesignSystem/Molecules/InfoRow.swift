import SwiftUI

/// Label on the left, value on the right — the shape a printed lab report uses.
///
/// An empty value renders as an em dash rather than as blank space, so a missing field reads as
/// "nothing was recorded" instead of looking like a layout fault.
struct InfoRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.appBody.weight(.semibold))
            Spacer(minLength: 12)
            Text(value.isEmpty ? "—" : value)
                .font(.appBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview("InfoRow") {
    VStack(spacing: 10) {
        InfoRow("MRN", "RM 240724-001")
        InfoRow("Address", "")
    }
    .padding()
}
