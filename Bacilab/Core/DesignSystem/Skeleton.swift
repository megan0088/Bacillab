import SwiftUI

// MARK: - Shimmer animation

private struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { proxy in
                let width = proxy.size.width
                LinearGradient(
                    stops: [
                        .init(color: .clear,               location: 0.0),
                        .init(color: .white.opacity(0.45),  location: 0.45),
                        .init(color: .white.opacity(0.45),  location: 0.55),
                        .init(color: .clear,               location: 1.0),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: width * 3)
                .offset(x: -width + phase * width * 3)
                .onAppear {
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
            }
            .clipped()
        )
    }
}

extension View {
    func skeletonShimmer() -> some View {
        modifier(Shimmer())
    }
}

// MARK: - Skeleton shapes

/// Teks satu baris
struct SkeletonLine: View {
    var width: CGFloat? = nil
    var height: CGFloat = 14

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2)
            .fill(Color(.systemGray5))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .skeletonShimmer()
    }
}

/// Avatar / icon bulat
struct SkeletonCircle: View {
    var size: CGFloat = 44

    var body: some View {
        Circle()
            .fill(Color(.systemGray5))
            .frame(width: size, height: size)
            .skeletonShimmer()
    }
}

/// Kotak / kartu / gambar
struct SkeletonBlock: View {
    var height: CGFloat = 80
    var cornerRadius: CGFloat = 16

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(.systemGray5))
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .skeletonShimmer()
    }
}

/// Badge / chip / pill
struct SkeletonPill: View {
    var width: CGFloat = 60
    var height: CGFloat = 28

    var body: some View {
        Capsule()
            .fill(Color(.systemGray5))
            .frame(width: width, height: height)
            .skeletonShimmer()
    }
}

// MARK: - Preview

#Preview("Skeleton shapes") {
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            SkeletonLine(width: 200, height: 32)
            SkeletonLine(width: 140, height: 14)
            SkeletonLine(height: 12)
            HStack { SkeletonCircle(size: 44); VStack(alignment: .leading, spacing: 6) { SkeletonLine(width: 160, height: 14); SkeletonLine(width: 100, height: 11) }; Spacer(); SkeletonPill() }
            SkeletonBlock(height: 100)
            HStack(spacing: 8) { SkeletonPill(width: 55); SkeletonPill(width: 70); SkeletonPill(width: 50) }
        }
        .padding(24)
    }
}
