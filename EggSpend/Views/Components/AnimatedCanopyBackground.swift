import SwiftUI

// MARK: - AnimatedCanopyBackground

/// Drop-in replacement for `LinearGradient.nestCanopy.ignoresSafeArea()`.
///
/// Combines the existing canopy gradient with a static warm top glow and a
/// handful of gently drifting leaves. Non-interactive — safe to place behind
/// any content.
///
/// Usage:
/// ```swift
/// ZStack {
///     AnimatedCanopyBackground()
///     YourContentView()
/// }
/// ```
struct AnimatedCanopyBackground: View {
    var body: some View {
        ZStack {
            LinearGradient.nestCanopy

            LinearGradient(
                colors: [
                    Color.yolk.opacity(0.18),
                    Color.nestLeafGreen.opacity(0.08),
                    Color.nestCream.opacity(0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black.opacity(0.75), location: 0.28),
                        .init(color: .clear, location: 0.55)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            FloatingLeavesView()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Preview

#Preview("AnimatedCanopyBackground") {
    ZStack {
        AnimatedCanopyBackground()
        Text("EggSpend")
            .font(.title.bold())
            .foregroundStyle(Color.nestBrown)
    }
}
