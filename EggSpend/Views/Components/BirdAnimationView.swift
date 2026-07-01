import SwiftUI

// MARK: - BirdAnimationView

/// Subtle animated background decoration showing small stylized birds flying
/// across the view from left to right at slightly different Y offsets and speeds.
///
/// The view is frameless (fills its container) and has `.allowsHitTesting(false)`
/// so it does not interfere with any taps beneath it.
///
/// Usage:
/// ```swift
/// ZStack {
///     BirdAnimationView()
///     YourContentView()
/// }
/// ```
struct BirdAnimationView: View {

    // MARK: Bird Configuration

    private struct BirdConfig: Sendable {
        let id: Int
        /// Fractional Y position within the view (0 = top, 1 = bottom)
        let yFraction: CGFloat
        /// How long it takes to cross the full width (seconds)
        let duration: Double
        /// Initial fractional X offset so birds don't all start at the same point
        let startOffset: CGFloat
        /// Scale factor relative to base size
        let scale: CGFloat
    }

    private let birds: [BirdConfig] = [
        BirdConfig(id: 0, yFraction: 0.22, duration: 9.0,  startOffset: 0.0,  scale: 1.0),
        BirdConfig(id: 1, yFraction: 0.38, duration: 11.5, startOffset: 0.45, scale: 0.82),
        BirdConfig(id: 2, yFraction: 0.14, duration: 13.0, startOffset: 0.70, scale: 0.70),
    ]

    // MARK: Animation State

    /// Each bird's horizontal progress: 0.0 = left edge, 1.0 = right edge.
    /// We initialise to the stagger start offsets so the birds appear spread out.
    @State private var offsets: [CGFloat] = [0.0, 0.45, 0.70]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let birdW: CGFloat = 20
            let birdH: CGFloat = 12

            ZStack {
                ForEach(birds, id: \.id) { config in
                    BirdShape()
                        .fill(Color.twig)
                        .frame(width: birdW * config.scale, height: birdH * config.scale)
                        .opacity(0.25)
                        // Map 0…1 progress to x position: start just off the left edge,
                        // finish just off the right edge.
                        .position(
                            x: lerp(from: -birdW, to: w + birdW, t: offsets[config.id]),
                            y: h * config.yFraction
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
        for config in birds {
            // Start from the bird's stagger offset so it's already mid-flight.
            // We animate from current staggered position to 1.0, then loop.
            // Because repeatForever restarts from the *beginning* of the animation
            // (i.e. from 0), we first push each bird to its start offset immediately,
            // then animate 0 → 1 forever.  The stagger is handled by giving the
            // initial offset value and then resetting to 0 before the loop starts.
            withAnimation(.linear(duration: config.duration * (1.0 - config.startOffset))) {
                offsets[config.id] = 1.0
            }
            // After the first partial traversal completes, switch to the full loop.
            // We schedule this via a Task so it fires after the initial animation ends.
            let delay = config.duration * (1.0 - config.startOffset)
            Task {
                try? await Task.sleep(for: .seconds(delay))
                await MainActor.run {
                    // Reset to left edge (no animation) then animate across forever.
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

// MARK: - BirdShape

/// A stylized bird in flight silhouette drawn as two upward-curved wings
/// meeting at a centre point — similar to a simple "M" or "∧∧" shape.
struct BirdShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        // Left wing: starts at left edge, arcs up to centre peak, then down to midpoint
        let leftEdge   = CGPoint(x: rect.minX,  y: rect.midY + h * 0.10)
        let leftPeak   = CGPoint(x: rect.midX * 0.5, y: rect.minY)
        let centre     = CGPoint(x: rect.midX,  y: rect.midY)
        let rightPeak  = CGPoint(x: rect.midX + w * 0.25, y: rect.minY)
        let rightEdge  = CGPoint(x: rect.maxX,  y: rect.midY + h * 0.10)

        // Left wing curve
        path.move(to: leftEdge)
        path.addCurve(
            to: leftPeak,
            control1: CGPoint(x: rect.minX  + w * 0.12, y: rect.midY - h * 0.3),
            control2: CGPoint(x: rect.midX  * 0.35,     y: rect.minY - h * 0.05)
        )
        path.addCurve(
            to: centre,
            control1: CGPoint(x: rect.midX  * 0.65,    y: rect.minY + h * 0.05),
            control2: CGPoint(x: rect.midX  - w * 0.04, y: rect.midY - h * 0.05)
        )

        // Right wing curve
        path.addCurve(
            to: rightPeak,
            control1: CGPoint(x: rect.midX  + w * 0.04, y: rect.midY - h * 0.05),
            control2: CGPoint(x: rect.midX  + w * 0.18, y: rect.minY + h * 0.05)
        )
        path.addCurve(
            to: rightEdge,
            control1: CGPoint(x: rect.midX  + w * 0.32, y: rect.minY - h * 0.05),
            control2: CGPoint(x: rect.maxX  - w * 0.12, y: rect.midY - h * 0.3)
        )

        return path
    }
}

// MARK: - Preview

#Preview("BirdAnimationView") {
    ZStack {
        Color.nestCream
            .ignoresSafeArea()

        BirdAnimationView()

        Text("Background birds flying past")
            .font(.headline)
            .foregroundStyle(Color.nestBrown)
    }
    .frame(height: 200)
}

#Preview("BirdShape") {
    BirdShape()
        .stroke(Color.twig, lineWidth: 1.5)
        .frame(width: 60, height: 36)
        .padding()
        .background(Color.nestCream)
}
