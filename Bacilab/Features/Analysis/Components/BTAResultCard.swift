import SwiftUI

struct BTAResultCard: View {
    let result: AnalysisResult

    var body: some View {
        VStack(spacing: 20) {
            gradeHeader

            HStack(spacing: 0) {
                statCell(icon: "number.circle.fill", value: "\(result.btaCount)", label: "Bacteria Found", color: gradeColor)
                Divider().frame(height: 50)
                statCell(icon: "gauge.with.dots.needle.67percent", value: "\(Int(result.confidence * 100))%", label: "Confidence", color: .blue)
            }
        }
        .padding(20)
        .background(gradeColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(gradeColor.opacity(0.25), lineWidth: 1)
        )
    }

    private var gradeHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(gradeColor.opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: gradeIcon)
                    .font(.title2)
                    .foregroundStyle(gradeColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("BTA Grade")
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
                Text(result.grade.rawValue)
                    .font(.appTitle)
                    .foregroundStyle(gradeColor)
            }
            Spacer()
        }
    }

    private func statCell(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.appHeadline)
            Text(label)
                .font(.appCaption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var gradeColor: Color {
        switch result.grade {
        case .negative: return .green
        case .scanty:   return .yellow
        case .plus1:    return .orange
        case .plus2:    return Color(red: 0.9, green: 0.3, blue: 0.1)
        case .plus3:    return .red
        }
    }

    private var gradeIcon: String {
        switch result.grade {
        case .negative: return "checkmark.seal.fill"
        case .scanty:   return "exclamationmark.triangle.fill"
        case .plus1, .plus2, .plus3: return "xmark.seal.fill"
        }
    }
}

// MARK: - Previews

#Preview("Negatif") {
    BTAResultCard(result: AnalysisResult(btaCount: 0, confidence: 0.98, grade: .negative, analyzedAt: .now))
        .padding()
}

#Preview("Scanty") {
    BTAResultCard(result: AnalysisResult(btaCount: 4, confidence: 0.87, grade: .scanty, analyzedAt: .now))
        .padding()
}

#Preview("1+") {
    BTAResultCard(result: AnalysisResult(btaCount: 12, confidence: 0.91, grade: .plus1, analyzedAt: .now))
        .padding()
}

#Preview("2+") {
    BTAResultCard(result: AnalysisResult(btaCount: 48, confidence: 0.95, grade: .plus2, analyzedAt: .now))
        .padding()
}

#Preview("3+") {
    BTAResultCard(result: AnalysisResult(btaCount: 130, confidence: 0.99, grade: .plus3, analyzedAt: .now))
        .padding()
}

#Preview("All Grades") {
    ScrollView {
        VStack(spacing: 16) {
            ForEach(BTAGrade.allCases, id: \.self) { grade in
                BTAResultCard(
                    result: AnalysisResult(
                        btaCount: [0, 4, 12, 48, 130][BTAGrade.allCases.firstIndex(of: grade)!],
                        confidence: 0.95,
                        grade: grade,
                        analyzedAt: .now
                    )
                )
            }
        }
        .padding()
    }
}
