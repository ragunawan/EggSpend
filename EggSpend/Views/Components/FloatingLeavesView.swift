import SwiftUI

// MARK: - FloatingLeavesView

/// Subtle animated background decoration showing small leaves drifting down
/// along varied seeded paths, looping forever.
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
        let startXFraction: CGFloat
        let endXFraction: CGFloat
        let midpointBias: CGFloat
        /// How long it takes to drift the full height (seconds)
        let duration: Double
        /// Initial fractional progress so leaves don't all start at the same point
        let startOffset: CGFloat
        /// Scale factor relative to base size
        let scale: CGFloat
        let swayAmplitude: CGFloat
        let swayFrequency: CGFloat
        let phase: CGFloat
        /// Full rotation range in degrees over one drift
        let rotationRange: Double
        let opacity: Double
        let color: Color
    }

    private let leaves: [LeafConfig] = [
        LeafConfig(id: 0, startXFraction: 0.10, endXFraction: 0.30, midpointBias: -0.08, duration: 17.0, startOffset: 0.00, scale: 1.0,  swayAmplitude: 10, swayFrequency: 1.4, phase: 0.2, rotationRange: 52,  opacity: 0.16, color: .nestLeafGreen),
        LeafConfig(id: 1, startXFraction: 0.86, endXFraction: 0.70, midpointBias: 0.10,  duration: 21.0, startOffset: 0.35, scale: 0.8,  swayAmplitude: 8,  swayFrequency: 1.9, phase: 1.1, rotationRange: -64, opacity: 0.13, color: .twig),
        LeafConfig(id: 2, startXFraction: 0.43, endXFraction: 0.55, midpointBias: 0.16,  duration: 25.0, startOffset: 0.60, scale: 0.65, swayAmplitude: 13, swayFrequency: 1.2, phase: 2.6, rotationRange: 43,  opacity: 0.14, color: .nestLeafGreen),
        LeafConfig(id: 3, startXFraction: 0.68, endXFraction: 0.45, midpointBias: -0.14, duration: 19.0, startOffset: 0.15, scale: 0.9,  swayAmplitude: 9,  swayFrequency: 2.1, phase: 3.5, rotationRange: -48, opacity: 0.12, color: .twig),
        LeafConfig(id: 4, startXFraction: 0.26, endXFraction: 0.18, midpointBias: 0.12,  duration: 23.0, startOffset: 0.80, scale: 0.7,  swayAmplitude: 12, swayFrequency: 1.6, phase: 4.4, rotationRange: 58,  opacity: 0.15, color: .nestLeafGreen),
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
                        .opacity(config.opacity)
                        .rotationEffect(.degrees(config.rotationRange * offsets[config.id]))
                        .position(
                            x: xPosition(for: config, width: w, progress: offsets[config.id]),
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

    private func xPosition(for config: LeafConfig, width: CGFloat, progress: CGFloat) -> CGFloat {
        let start = width * config.startXFraction
        let end = width * config.endXFraction
        let middle = width * ((config.startXFraction + config.endXFraction) / 2 + config.midpointBias)
        let curve = quadraticBezier(start: start, control: middle, end: end, t: progress)
        let wobble = config.swayAmplitude * sin((progress * .pi * 2 * config.swayFrequency) + config.phase)
        return curve + wobble
    }

    private func quadraticBezier(start: CGFloat, control: CGFloat, end: CGFloat, t: CGFloat) -> CGFloat {
        let inverse = 1 - t
        return inverse * inverse * start + 2 * inverse * t * control + t * t * end
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
