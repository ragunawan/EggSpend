import SwiftUI

// MARK: - EggProgressView

/// An animated egg-shaped budget progress indicator.
///
/// The egg fills from the bottom upward as `progress` increases from 0.0 to 1.0.
/// Fill color transitions from safe (eggBlue) → warning (yolk) → over-budget (orange/red).
/// When progress exceeds 1.0 a cracked-egg overlay is shown.
///
/// Usage:
/// ```swift
/// EggProgressView(progress: 0.72)
/// EggProgressView(progress: 1.15, size: 80)
/// ```
public struct EggProgressView: View {

    // MARK: Public API

    /// Budget consumption ratio. Values above 1.0 are clamped to 1.0 for the
    /// fill level, but trigger the "over budget" crack overlay and red color.
    public let progress: Double

    /// Diameter of the bounding square the egg is drawn into.
    public var size: CGFloat = 60

    // MARK: Init

    public init(progress: Double, size: CGFloat = 60) {
        self.progress = progress
        self.size = size
    }

    // MARK: Derived

    private var clampedProgress: Double { min(max(progress, 0), 1.0) }
    private var isOverBudget: Bool { progress > 1.0 }

    private var fillColor: Color {
        switch clampedProgress {
        case ..<0.7:  return .eggBlue
        case ..<0.9:  return .yolk
        default:
            return isOverBudget ? .red : .orange
        }
    }

    private var percentText: String {
        let pct = Int((progress * 100).rounded())
        return "\(pct)%"
    }

    // MARK: Body

    public var body: some View {
        ZStack {
            // Background egg (unfilled shell)
            EggProgressShape()
                .fill(Color.nestCream.opacity(0.6))
                .overlay(
                    EggProgressShape()
                        .stroke(Color.twig.opacity(0.4), lineWidth: 1.5)
                )

            // Liquid fill — clips the color rect to the egg shape
            GeometryReader { geo in
                let eggH = geo.size.height
                let fillH = eggH * clampedProgress

                Rectangle()
                    .fill(fillColor)
                    .frame(height: fillH)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .animation(.spring(response: 0.7, dampingFraction: 0.8), value: clampedProgress)
                    .clipShape(EggProgressShape())
                    .opacity(0.82)
            }

            // Crack overlay when over budget
            if isOverBudget {
                CrackShape()
                    .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .blendMode(.overlay)
            }

            // Percentage label
            Text(percentText)
                .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
                .foregroundStyle(labelColor)
                .shadow(color: .black.opacity(0.15), radius: 1, x: 0, y: 1)
        }
        .frame(width: size * 0.72, height: size)
        // Animate fill color transitions
        .animation(.spring(response: 0.7, dampingFraction: 0.8), value: fillColor.description)
    }

    // MARK: Label color

    private var labelColor: Color {
        // Use a color that contrasts well against the fill level at center
        clampedProgress > 0.5 ? .white : Color.nestBrown
    }
}

// MARK: - EggProgressShape

/// Egg outline: wider at the bottom, narrower at the top, taller than wide.
/// The bounding rect is used as-given; caller sizes the frame.
struct EggProgressShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let cx = rect.midX

        // Top point (narrower)
        path.move(to: CGPoint(x: cx, y: rect.minY))

        // Right side — control points make top narrow, bottom wider
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: h * 0.62 + rect.minY),
            control1: CGPoint(x: cx + w * 0.36, y: rect.minY),
            control2: CGPoint(x: rect.maxX, y: h * 0.32 + rect.minY)
        )
        // Bottom right arc
        path.addCurve(
            to: CGPoint(x: cx, y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: h * 0.88 + rect.minY),
            control2: CGPoint(x: cx + w * 0.42, y: rect.maxY)
        )
        // Bottom left arc
        path.addCurve(
            to: CGPoint(x: rect.minX, y: h * 0.62 + rect.minY),
            control1: CGPoint(x: cx - w * 0.42, y: rect.maxY),
            control2: CGPoint(x: rect.minX, y: h * 0.88 + rect.minY)
        )
        // Left side back to top
        path.addCurve(
            to: CGPoint(x: cx, y: rect.minY),
            control1: CGPoint(x: rect.minX, y: h * 0.32 + rect.minY),
            control2: CGPoint(x: cx - w * 0.36, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - CrackShape

/// A zig-zag crack line drawn from the upper-middle of the egg downward.
struct CrackShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX
        let startY = rect.minY + rect.height * 0.15

        // Zig-zag crack
        path.move(to: CGPoint(x: cx, y: startY))
        path.addLine(to: CGPoint(x: cx + rect.width * 0.07, y: startY + rect.height * 0.10))
        path.addLine(to: CGPoint(x: cx - rect.width * 0.06, y: startY + rect.height * 0.20))
        path.addLine(to: CGPoint(x: cx + rect.width * 0.05, y: startY + rect.height * 0.30))
        path.addLine(to: CGPoint(x: cx - rect.width * 0.04, y: startY + rect.height * 0.38))
        return path
    }
}

// MARK: - Preview

#Preview("EggProgressView States") {
    HStack(spacing: 20) {
        VStack(spacing: 6) {
            EggProgressView(progress: 0.30, size: 70)
            Text("30%")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        VStack(spacing: 6) {
            EggProgressView(progress: 0.72, size: 70)
            Text("72%")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        VStack(spacing: 6) {
            EggProgressView(progress: 0.88, size: 70)
            Text("88%")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        VStack(spacing: 6) {
            EggProgressView(progress: 1.0, size: 70)
            Text("100%")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        VStack(spacing: 6) {
            EggProgressView(progress: 1.18, size: 70)
            Text("118% (over)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
    .padding(24)
    .background(Color.nestCream)
}
