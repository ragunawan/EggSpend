import SwiftUI

enum Space {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}

enum Radius {
    static let control: CGFloat = 8
    static let card: CGFloat = 12
    static let sheet: CGFloat = 16
}

enum NestType {
    static let hero = Font.system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit()
    static let stat = Font.system(.title3, design: .rounded, weight: .semibold).monospacedDigit()
    static let rowTitle = Font.body
    static let amount = Font.callout.weight(.semibold).monospacedDigit()
    static let meta = Font.caption
    static let overline = Font.caption2.weight(.semibold)
}

extension Animation {
    static let quickFade = Animation.easeOut(duration: 0.2)
}

private struct ChartDetailCalloutStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            // Chart annotations propose a constrained width during selection-driven
            // re-layout; without this, currency text inside can truncate ("$...")
            // instead of the callout growing to fit its content.
            .fixedSize()
            .padding(.horizontal, Space.sm)
            .padding(.vertical, 5)
            .background(
                Color(lightHex: "FFFFFF", darkHex: "1E1A16"),
                in: RoundedRectangle(cornerRadius: Radius.control)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Radius.control)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
    }
}

extension View {
    func chartDetailCalloutStyle() -> some View {
        modifier(ChartDetailCalloutStyle())
    }
}
