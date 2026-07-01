import SwiftUI

// MARK: - FloatingLeavesView

/// Subtle animated background decoration showing small leaves drifting
/// diagonally downward and gently rotating, looping forever.
///
/// The view is frameless (fills its container) and has `.allowsHitTesting(false)`
/// so it does not interfere with any taps beneath it.
///
/// Usage:
/// ```swift
/// ZStack {
///     FloatingLeavesView()
///     YourContentView()
/// }
/// ```
struct FloatingLeavesView: View {

    // MARK: Leaf Configuration

    private struct LeafConfig: Sendable {
        let id: Int
        /// Fractional X position within the view (0 = left, 1 = right)
        let xFraction: CGFloat
        /// How long it takes to drift the full height (seconds)
        let duration: Double
        /// Initial fractional progress so leaves don't all start at the same point
        let startOffset: CGFloat
        /// Scale factor relative to base size
        let scale: CGFloat
        /// Horizontal sway amplitude in points
        let sway: CGFloat
        /// Full rotation range in degrees over one drift
        let rotationRange: Double
        let color: Color
    }

    private let leaves: [LeafConfig] = [
        LeafConfig(id: 0, xFraction: 0.12, duration: 16.0, startOffset: 0.0,  scale: 1.0,  sway: 14, rotationRange: 50,  color: .nestLeafGreen),
        LeafConfig(id: 1, xFraction: 0.82, duration: 20.0, startOffset: 0.35, scale: 0.8,  sway: 10, rotationRange: -60, color: .twig),
        LeafConfig(id: 2, xFraction: 0.45, duration: 24.0, startOffset: 0.6,  scale: 0.65, sway: 18, rotationRange: 40,  color: .nestLeafGreen),
        LeafConfig(id: 3, xFraction: 0.65, duration: 18.0, startOffset: 0.15, scale: 0.9,  sway: 12, rotationRange: -45, color: .twig),
        LeafConfig(id: 4, xFraction: 0.28, duration: 22.0, startOffset: 0.8,  scale: 0.7,  sway: 16, rotationRange: 55,  color: .nestLeafGreen),
    ]

    // MARK: Animation State

    /// Each leaf's vertical progress: 0.0 = top edge, 1.0 = bottom edge.
    @State private var offsets: [CGFloat] = [0.0, 0.35, 0.6, 0.15, 0.8]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let leafW: CGFloat = 16
            let leafH: CGFloat = 20

            ZStack {
                ForEach(leaves, id: \.id) { config in
                    LeafShape()
                        .fill(config.color)
                        .frame(width: leafW * config.scale, height: leafH * config.scale)
                        .opacity(0.16)
                        .rotationEffect(.degrees(config.rotationRange * offsets[config.id]))
                        .position(
                            x: w * config.xFraction + config.sway * sin(offsets[config.id] * .pi * 2),
                            y: lerp(from: -leafH, to: h + leafH, t: offsets[config.id])
                        )
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            startAnimations()
        }
    }

    // MARK: - Animation

    private func startAnimations() {
        for config in leaves {
            // Start from the leaf's stagger offset so it's already mid-drift,
            // then loop from the top forever once the initial partial run ends.
            withAnimation(.linear(duration: config.duration * (1.0 - config.startOffset))) {
                offsets[config.id] = 1.0
            }
            let delay = config.duration * (1.0 - config.startOffset)
            Task {
                try? await Task.sleep(for: .seconds(delay))
                await MainActor.run {
                    offsets[config.id] = 0.0
                    withAnimation(
                        .linear(duration: config.duration)
                        .repeatForever(autoreverses: false)
                    ) {
                        offsets[config.id] = 1.0
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func lerp(from start: CGFloat, to end: CGFloat, t: CGFloat) -> CGFloat {
        start + (end - start) * t
    }
}

// MARK: - LeafShape

/// A simple pinched-teardrop leaf silhouette with a center vein.
struct LeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        let top = CGPoint(x: rect.midX, y: rect.minY)
        let bottom = CGPoint(x: rect.midX, y: rect.maxY)

        path.move(to: top)
        path.addCurve(
            to: bottom,
            control1: CGPoint(x: rect.maxX + w * 0.15, y: rect.minY + h * 0.35),
            control2: CGPoint(x: rect.midX + w * 0.1, y: rect.maxY - h * 0.1)
        )
        path.addCurve(
            to: top,
            control1: CGPoint(x: rect.midX - w * 0.1, y: rect.maxY - h * 0.1),
            control2: CGPoint(x: rect.minX - w * 0.15, y: rect.minY + h * 0.35)
        )
        path.closeSubpath()

        return path
    }
}

// MARK: - Preview

#Preview("FloatingLeavesView") {
    ZStack {
        LinearGradient.nestCanopy.ignoresSafeArea()
        FloatingLeavesView()
        Text("Drifting leaves")
            .font(.headline)
            .foregroundStyle(Color.nestBrown)
    }
}

#Preview("LeafShape") {
    LeafShape()
        .fill(Color.nestLeafGreen)
        .frame(width: 40, height: 50)
        .padding()
        .background(Color.nestCream)
}
