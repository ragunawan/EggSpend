import SwiftUI

// MARK: - AnimatedCanopyBackground

/// Drop-in replacement for `LinearGradient.nestCanopy.ignoresSafeArea()`.
///
/// Combines the existing canopy gradient with a slow, drifting shaft of
/// dappled light and a handful of gently falling leaves so every screen that
/// uses the canopy backdrop has continuous, ambient motion rather than a
/// static wash. Non-interactive — safe to place behind any content.
///
/// Usage:
/// ```swift
/// ZStack {
///     AnimatedCanopyBackground()
///     YourContentView()
/// }
/// ```
struct AnimatedCanopyBackground: View {

    @State private var lightOffset: CGFloat = -0.3

    var body: some View {
        ZStack {
            LinearGradient.nestCanopy

            GeometryReader { geo in
                // `.yolk` (not `.nestCream`) so this reads as warm light in both
                // color schemes — `nestCream` is deliberately dark in dark mode
                // as a background tint, which turned this into a murky smudge.
                RadialGradient(
                    colors: [Color.yolk.opacity(0.16), Color.yolk.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: geo.size.width * 0.6
                )
                .frame(width: geo.size.width * 0.9, height: geo.size.width * 0.9)
                .position(
                    x: geo.size.width * (0.5 + lightOffset),
                    y: geo.size.height * 0.25
                )
            }

            FloatingLeavesView()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 20).repeatForever(autoreverses: true)) {
                lightOffset = 0.3
            }
        }
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
