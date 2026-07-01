import SwiftUI
import UIKit

// MARK: - Color Extensions

extension Color {

    // MARK: Hex Initializers

    /// Parses a 6-character hex string with an optional `#` prefix.
    init?(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.hasPrefix("#") ? String(cleaned.dropFirst()) : cleaned
        guard cleaned.count == 6,
              let value = UInt64(cleaned, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    /// Creates an adaptive color that switches between light and dark hex values
    /// based on the current color scheme.
    init(lightHex: String, darkHex: String) {
        let uiColor = UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? darkHex : lightHex
            var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned = cleaned.hasPrefix("#") ? String(cleaned.dropFirst()) : cleaned
            guard cleaned.count == 6,
                  let value = UInt64(cleaned, radix: 16) else { return .label }
            let r = CGFloat((value >> 16) & 0xFF) / 255
            let g = CGFloat((value >> 8) & 0xFF) / 255
            let b = CGFloat(value & 0xFF) / 255
            return UIColor(red: r, green: g, blue: b, alpha: 1)
        }
        self.init(uiColor: uiColor)
    }

    // MARK: Hex Export

    /// Returns the resolved hex string (e.g. "5C3D1E") using the light-mode
    /// trait collection so the value is deterministic when stored.
    var hexString: String {
        let resolved = UIColor(self).resolvedColor(
            with: UITraitCollection(userInterfaceStyle: .light)
        )
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X",
                      Int((r * 255).rounded()),
                      Int((g * 255).rounded()),
                      Int((b * 255).rounded()))
    }

    // MARK: Semantic Palette

    /// Warm wood brown — primary brand color.
    static let nestBrown = Color(lightHex: "5C3D1E", darkHex: "C8A870")

    /// Parchment cream — background tint.
    static let nestCream = Color(lightHex: "FAF0DC", darkHex: "2A1A0A")

    /// Robin egg blue — accent for income / assets.
    static let eggBlue = Color(lightHex: "5BA4C1", darkHex: "72B8D4")

    /// Leaf green — positive indicators.
    static let nestLeafGreen = Color(lightHex: "3D7A3B", darkHex: "5BAA59")

    /// Golden yolk — primary interactive accent.
    static let yolk = Color(lightHex: "D4820A", darkHex: "F0B040")

    /// Bark / twig — secondary muted brown.
    static let twig = Color(lightHex: "9E7348", darkHex: "B08F63")

    /// Deep canopy green — background-only wash, kept dark and desaturated
    /// in dark mode so it reads as a tinted dark background rather than a
    /// bright accent color. `nestLeafGreen` stays bright for text/icons.
    static let nestCanopyTop = Color(lightHex: "3D7A3B", darkHex: "132313")
}

// MARK: - Gradient Extensions

extension LinearGradient {

    /// Soft canopy gradient — green fading to cream, top to bottom.
    static let nestCanopy = LinearGradient(
        colors: [Color.nestCanopyTop.opacity(0.55), Color.nestCream.opacity(0.85)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Warm golden yolk glow gradient.
    static let yolkGlow = LinearGradient(
        colors: [Color.yolk, Color(lightHex: "F0A030", darkHex: "FFD070")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - View Modifiers

private struct NestCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(
                color: Color.nestBrown.opacity(0.12),
                radius: 8,
                x: 0,
                y: 3
            )
    }
}

extension View {
    func nestCard() -> some View {
        modifier(NestCardModifier())
    }
}

extension Calendar {
    func isDateInCurrentMonth(_ date: Date) -> Bool {
        let now = Date.now
        return component(.month, from: date) == component(.month, from: now)
            && component(.year,  from: date) == component(.year,  from: now)
    }

    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }
}
