import SwiftUI

/// Keypad numerik untuk mengganti hitungan satu lapang.
///
/// Mengganti angka, bukan menaik-turunkannya: layar lama memakai tombol ± pada total lintas
/// seluruh lapang, sehingga mengoreksi hitungan 400 berarti 400 ketukan.
struct CountKeypad: View {
    let text: String
    let onDigit: (String) -> Void
    let onDelete: () -> Void
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]]

    var body: some View {
        VStack(spacing: 14) {
            Text(text.isEmpty ? "—" : text)
                .font(.appTitle.weight(.bold))
                .foregroundStyle(text.isEmpty ? .tertiary : .primary)
                .frame(height: 54)
                .contentTransition(.numericText())

            ForEach(rows, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { digit in
                        key(digit) { onDigit(digit) }
                    }
                }
            }

            HStack(spacing: 10) {
                key("0") { onDigit("0") }
                Button(action: onDelete) {
                    Image(systemName: "delete.left")
                        .font(.appHeading)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 12))
                }
                .foregroundStyle(.primary)
            }

            HStack(spacing: 10) {
                Button("Cancel", action: onCancel)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.secondary)

                Button("Save", action: onConfirm)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                    .fontWeight(.semibold)
            }
        }
        .padding(20)
    }

    private func key(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.appHeading.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
        }
        .foregroundStyle(.primary)
    }
}

#Preview("Keypad") {
    CountKeypad(text: "12", onDigit: { _ in }, onDelete: {}, onConfirm: {}, onCancel: {})
}
