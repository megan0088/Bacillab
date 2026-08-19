import SwiftUI

struct NewAnalysisCard: View {
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("New Analysis")
                        .font(.appHeading .weight(.bold))
                    Text("Input patient")
                        .font(.appCaption)
                        .opacity(0.9)
                }
                Spacer()
                Image(systemName: "plus.circle.fill").font(.appTitle)
            }
            .foregroundStyle(.white)
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 20)
            )
        }
    }
}

#Preview("NewAnalysisCard") {
    NewAnalysisCard {}
        .padding()
}
