import SwiftUI

// MARK: - NestHeaderView

/// Decorative hero graphic showing a bird's nest with three robin eggs.
/// Designed to fill a ~200×120pt frame at the top of the Dashboard.
struct NestHeaderView: View {

    @State private var nestScale: CGFloat = 0.4
    @State private var nestOpacity: Double = 0
    @State private var eggScales: [CGFloat] = [0, 0, 0]
    @State private var eggOffsets: [CGFloat] = [0, 0, 0]
    @State private var crackedEggIndex: Int? = nil
    @State private var lastTapTime: Date = .distantPast

    /// Fractional (x, y) position of each egg within the nest bowl.
    private let eggPositions: [(x: CGFloat, y: CGFloat)] = [
        (0.34, 0.52),
        (0.50, 0.46),
        (0.66, 0.53),
    ]

    /// Taps closer together than this feel deliberate/rapid rather than incidental.
    private let fastTapThreshold: TimeInterval = 0.3

    var body: some View {
        Canvas { context, size in
            drawNest(context: context, size: size)
        }
        .overlay(eggsOverlay)
        .scaleEffect(nestScale)
        .opacity(nestOpacity)
        .contentShape(Rectangle())
        .onTapGesture { handleTap() }
        .onAppear {
            // Nest scales in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                nestScale = 1.0
                nestOpacity = 1.0
            }
            // Eggs bounce in with staggered delays
            let entranceDelays: [Double] = [0.25, 0.4, 0.55]
            for index in eggScales.indices {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.55).delay(entranceDelays[index])) {
                    eggScales[index] = 1.0
                }
            }
        }
    }

    // MARK: - Tap interaction

    /// Every tap makes the eggs hop up and spring back into the nest. Tapping
    /// again before the previous hop settles cracks a random egg, which
    /// respawns on its own a few seconds later.
    private func handleTap() {
        let now = Date()
        let isFastTap = now.timeIntervalSince(lastTapTime) < fastTapThreshold
        lastTapTime = now

        jumpAllEggs()

        if isFastTap && crackedEggIndex == nil {
            crackRandomEgg()
        }
    }

    private func jumpAllEggs() {
        for index in eggOffsets.indices {
            let delay = Double(index) * 0.05
            withAnimation(.spring(response: 0.22, dampingFraction: 0.5).delay(delay)) {
                eggOffsets[index] = -20
            }
            Task {
                try? await Task.sleep(for: .seconds(delay + 0.16))
                await MainActor.run {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.45)) {
                        eggOffsets[index] = 0
                    }
                }
            }
        }
    }

    private func crackRandomEgg() {
        let index = Int.random(in: eggPositions.indices)
        crackedEggIndex = index
        Task {
            try? await Task.sleep(for: .seconds(5))
            await MainActor.run {
                respawnEgg(at: index)
            }
        }
    }

    private func respawnEgg(at index: Int) {
        guard crackedEggIndex == index else { return }
        crackedEggIndex = nil
        eggScales[index] = 0
        withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) {
            eggScales[index] = 1.0
        }
    }

    // MARK: - Nest Canvas Drawing

    private func drawNest(context: GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height

        // Basket bowl — a filled arc/ellipse clipped to bottom half
        var bowlPath = Path()
        bowlPath.addArc(
            center: CGPoint(x: w * 0.5, y: h * 0.38),
            radius: w * 0.4,
            startAngle: .degrees(0),
            endAngle: .degrees(180),
            clockwise: false
        )
        bowlPath.addLine(to: CGPoint(x: w * 0.1, y: h * 0.38))

        // Fill bowl with nestBrown
        context.fill(bowlPath, with: .color(.nestBrown))

        let rimRect = CGRect(
            x: w * 0.08,
            y: h * 0.28,
            width: w * 0.84,
            height: h * 0.22
        )

        // Cross-hatched twig texture — short diagonal strokes across the bowl area
        let twigColor = GraphicsContext.Shading.color(Color.twig.opacity(0.55))
        let strokeStyle = StrokeStyle(lineWidth: 1.2, lineCap: .round)

        // Forward diagonal strokes ( \ direction )
        let bowlLeft  = w * 0.12
        let bowlRight = w * 0.88
        let bowlTop   = h * 0.35
        let bowlBot   = h * 0.90
        let step: CGFloat = 9

        context.drawLayer { hatchContext in
            hatchContext.clip(to: bowlPath)

            var x = bowlLeft - (bowlBot - bowlTop)
            while x < bowlRight {
                let x0 = x
                let y0 = bowlTop
                let x1 = x + (bowlBot - bowlTop)

                // Clamp to the broad nest area before clipping to the exact bowl curve.
                let startX = max(x0, bowlLeft)
                let startY = y0 + (startX - x0)
                let endX   = min(x1, bowlRight)
                let endY   = y0 + (endX - x0)

                if startX < endX {
                    var stroke = Path()
                    stroke.move(to: CGPoint(x: startX, y: startY))
                    stroke.addLine(to: CGPoint(x: endX, y: endY))
                    hatchContext.stroke(stroke, with: twigColor, style: strokeStyle)
                }
                x += step
            }

            // Back diagonal strokes ( / direction )
            x = bowlLeft
            while x < bowlRight + (bowlBot - bowlTop) {
                let x0 = x
                let y0 = bowlBot
                let x1 = x - (bowlBot - bowlTop)
                let y1 = bowlTop

                let startX = max(min(x0, x1), bowlLeft)
                let endX   = min(max(x0, x1), bowlRight)

                if startX < endX {
                    // Interpolate y
                    let totalDX = x0 - x1
                    let startY = (totalDX == 0) ? y0 : y0 + (y1 - y0) * ((startX - x0) / (x1 - x0))
                    let endY   = (totalDX == 0) ? y1 : y0 + (y1 - y0) * ((endX   - x0) / (x1 - x0))
                    var stroke = Path()
                    stroke.move(to: CGPoint(x: startX, y: startY))
                    stroke.addLine(to: CGPoint(x: endX, y: endY))
                    hatchContext.stroke(stroke, with: twigColor, style: strokeStyle)
                }
                x += step
            }
        }

        // Rim ellipse for depth, drawn over hatching so the nest edge stays crisp.
        var rimPath = Path()
        rimPath.addEllipse(in: rimRect)
        context.fill(rimPath, with: .color(Color.nestBrown.opacity(0.75)))

        // Draw twig stroke rim on top
        var rimStroke = Path()
        rimStroke.addEllipse(in: rimRect)
        context.stroke(rimStroke, with: .color(.twig), lineWidth: 2.5)

        // A few random-looking short twig accent strokes on the rim
        let twigAccents: [(CGPoint, CGPoint)] = [
            (CGPoint(x: w * 0.15, y: h * 0.34), CGPoint(x: w * 0.22, y: h * 0.30)),
            (CGPoint(x: w * 0.25, y: h * 0.28), CGPoint(x: w * 0.35, y: h * 0.33)),
            (CGPoint(x: w * 0.65, y: h * 0.29), CGPoint(x: w * 0.75, y: h * 0.34)),
            (CGPoint(x: w * 0.78, y: h * 0.31), CGPoint(x: w * 0.87, y: h * 0.27)),
            (CGPoint(x: w * 0.42, y: h * 0.26), CGPoint(x: w * 0.52, y: h * 0.30)),
        ]
        for (start, end) in twigAccents {
            var twig = Path()
            twig.move(to: start)
            twig.addLine(to: end)
            context.stroke(twig, with: .color(Color.twig.opacity(0.8)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }

    // MARK: - Eggs Overlay

    @ViewBuilder
    private var eggsOverlay: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ForEach(eggPositions.indices, id: \.self) { index in
                let pos = eggPositions[index]
                ZStack {
                    EggShape()
                        .fill(eggGradient)
                    if crackedEggIndex == index {
                        CrackShape()
                            .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                            .blendMode(.overlay)
                    }
                }
                .frame(width: w * 0.18, height: w * 0.13)
                .scaleEffect(eggScales[index])
                .offset(y: eggOffsets[index])
                .position(x: w * pos.x, y: h * pos.y)
            }
        }
    }

    private var eggGradient: RadialGradient {
        RadialGradient(
            colors: [
                Color.eggBlue.opacity(0.55),
                Color.eggBlue,
            ],
            center: .init(x: 0.35, y: 0.3),
            startRadius: 0,
            endRadius: 22
        )
    }
}

// MARK: - EggShape (simple)

/// A simple egg ellipse — slightly taller than wide, used only inside NestHeaderView.
private struct EggShape: Shape {
    func path(in rect: CGRect) -> Path {
        // Use a capsule-like shape: standard ellipse but we shift the center
        // upward slightly so the bottom is wider than the top via a bezier.
        var path = Path()
        let w = rect.width
        let h = rect.height
        let cx = rect.midX
        let cy = rect.midY

        // Top point
        path.move(to: CGPoint(x: cx, y: rect.minY))
        // Right side — narrower at top
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: cy + h * 0.15),
            control1: CGPoint(x: cx + w * 0.38, y: rect.minY),
            control2: CGPoint(x: rect.maxX, y: cy - h * 0.15)
        )
        // Bottom right
        path.addCurve(
            to: CGPoint(x: cx, y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: cy + h * 0.45),
            control2: CGPoint(x: cx + w * 0.38, y: rect.maxY)
        )
        // Bottom left
        path.addCurve(
            to: CGPoint(x: rect.minX, y: cy + h * 0.15),
            control1: CGPoint(x: cx - w * 0.38, y: rect.maxY),
            control2: CGPoint(x: rect.minX, y: cy + h * 0.45)
        )
        // Back to top
        path.addCurve(
            to: CGPoint(x: cx, y: rect.minY),
            control1: CGPoint(x: rect.minX, y: cy - h * 0.15),
            control2: CGPoint(x: cx - w * 0.38, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Preview

#Preview {
    NestHeaderView()
        .frame(width: 200, height: 120)
        .padding()
        .background(Color.nestCream)
}
