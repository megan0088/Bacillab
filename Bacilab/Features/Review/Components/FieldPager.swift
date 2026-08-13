import SwiftUI

/// Deretan nomor lapang, satu dot per lapang.
///
/// Dot bertanda oranye adalah lapang yang belum punya angka — gagal dianalisis atau masih
/// diantre. Keduanya keluar dari pembilang dan penyebut, jadi analis harus bisa menemukannya
/// tanpa membuka satu per satu.
struct FieldPager: View {
    let fields: [FieldRecord]
    let selectedID: UUID?
    let onSelect: (UUID) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(fields) { field in
                        dot(for: field)
                            .id(field.id)
                            .onTapGesture { onSelect(field.id) }
                    }
                }
                .padding(.horizontal, 20)
            }
            .onChange(of: selectedID) { _, new in
                guard let new else { return }
                withAnimation { proxy.scrollTo(new, anchor: .center) }
            }
        }
    }

    private func dot(for field: FieldRecord) -> some View {
        let isSelected = field.id == selectedID
        let needsAttention = !field.isExcluded && field.effectiveCount == nil

        return ZStack(alignment: .topTrailing) {
            Circle()
                .fill(isSelected ? Color.accentColor : Color(.systemGray5))
                .frame(width: 34, height: 34)
                .overlay {
                    Text("\(field.index + 1)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? .white : .primary)
                }
                .overlay {
                    // Lapang yang dibuang tetap terlihat, tapi dicoret — menghilangkannya
                    // akan membuat penomoran melompat dan analis kehilangan jejak.
                    if field.isExcluded {
                        Circle().stroke(Color(.systemGray), lineWidth: 1)
                        Rectangle()
                            .fill(Color(.systemGray))
                            .frame(width: 24, height: 1.5)
                            .rotationEffect(.degrees(-45))
                    }
                }
                .opacity(field.isExcluded ? 0.45 : 1)

            if needsAttention {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
            }
        }
        .frame(width: 38, height: 38)
    }
}

#Preview("Field pager") {
    let session = ExamSession()
    for i in 0..<8 {
        let f = session.appendField(imageFileName: "f.jpg")
        if i != 3 {
            session.setAnalysis(FieldAnalysis(
                readings: [DetectorReading(detector: .resnet, btaCount: i,
                                           confidence: 0.8, elapsed: 0.4)],
                primary: .resnet), for: f.id)
        }
        if i == 5 { session.setExcluded(true, for: f.id) }
    }
    return FieldPager(fields: session.fields,
                      selectedID: session.fields.first?.id,
                      onSelect: { _ in })
        .padding(.vertical)
}
