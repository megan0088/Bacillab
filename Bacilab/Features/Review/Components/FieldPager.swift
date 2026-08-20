import SwiftUI

/// Deretan nomor lapang, satu dot per lapang.
///
/// Sized so roughly five fit across a phone at once, with the sixth just peeking — the peek is
/// what tells the analyst the row scrolls at all. A dot is 56pt inside a 60pt box, and the
/// remaining 4pt is what the orange marker overhangs into.
///
/// The number steps up to `.appHeading` rather than staying at `.appCaption`, because at 56pt a
/// 13pt digit reads as an afterthought. 22pt keeps roughly the proportion the smaller dot had;
/// there is no size in between, and inventing one would break the four-step scale.
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
                HStack(spacing: 10) {
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
                .frame(width: 56, height: 56)
                .overlay {
                    Text("\(field.index + 1)")
                        .font(.appHeading.weight(.semibold))
                        .foregroundStyle(isSelected ? .white : .primary)
                }
                .overlay {
                    // Lapang yang dibuang tetap terlihat, tapi dicoret — menghilangkannya
                    // akan membuat penomoran melompat dan analis kehilangan jejak.
                    if field.isExcluded {
                        Circle().stroke(Color(.systemGray), lineWidth: 1)
                        Rectangle()
                            .fill(Color(.systemGray))
                            .frame(width: 40, height: 2.5)
                            .rotationEffect(.degrees(-45))
                    }
                }
                .opacity(field.isExcluded ? 0.45 : 1)

            if needsAttention {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
            }
        }
        .frame(width: 60, height: 60)
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
