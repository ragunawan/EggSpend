import SwiftUI

struct ThinProgressBar: View {
    let progress: Double
    var color: Color = .positive
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.textSecondaryWarm.opacity(0.15))
                Capsule()
                    .fill(color)
                    .frame(width: geometry.size.width * min(max(progress, 0), 1))
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

#Preview("Thin Progress Bar") {
    VStack(spacing: Space.lg) {
        ThinProgressBar(progress: 0.45)
        ThinProgressBar(progress: 0.85, color: .warningTone)
        ThinProgressBar(progress: 1.2, color: .negative)
    }
    .padding(Space.lg)
}
