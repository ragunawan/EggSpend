import SwiftUI

struct CurrencyKeypadView: View {
    @Binding var amountText: String

    @ScaledMetric(relativeTo: .title3) private var keyHeight: CGFloat = 52

    // Cents fill in from the right as you type — "1999" reads as $19.99,
    // "225" as $2.25 — so there's no manual decimal placement; "00" takes
    // that key's place as the standard complement (quickly reaches whole-
    // dollar amounts, e.g. "5" then "00" → $5.00).
    private let rows = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["00", "0", "backspace"]
    ]

    // Caps entry at $99,999,999.99 — generous for any real transaction,
    // just a guard against runaway digit-mashing overflowing Int.
    private static let maxDigits = 10

    private var resolvedKeyHeight: CGFloat {
        max(44, keyHeight)
    }

    var body: some View {
        Grid(horizontalSpacing: Space.sm, verticalSpacing: Space.sm) {
            ForEach(rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { key in
                        Button {
                            handle(key)
                        } label: {
                            label(for: key)
                                .font(.title3.weight(.semibold).monospacedDigit())
                                .frame(maxWidth: .infinity, minHeight: resolvedKeyHeight)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                        .background(
                            Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08))
                        }
                        .accessibilityLabel(accessibilityLabel(for: key))
                        .accessibilityAddTraits(.isKeyboardKey)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func label(for key: String) -> some View {
        switch key {
        case "backspace":
            Image(systemName: "delete.left")
                .accessibilityHidden(true)
        default:
            Text(key)
        }
    }

    private func accessibilityLabel(for key: String) -> Text {
        switch key {
        case "00": Text("Double zero")
        case "backspace": Text("Backspace")
        default: Text(key)
        }
    }

    private func handle(_ key: String) {
        switch key {
        case "backspace":
            setCents(currentCents / 10)
        case "00":
            appendDigits("00")
        default:
            appendDigits(key)
        }
    }

    /// Shifts `digits` in from the right, as if typed on a cents-entry
    /// register: existing digits move left and the rightmost two digits
    /// are always the cents place (e.g. current "19.99" + "9" → "199.99").
    private func appendDigits(_ digits: String) {
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return }
        let combined = String(currentCents) + digits
        guard combined.count <= Self.maxDigits else { return }
        setCents(Int(combined) ?? currentCents)
    }

    private var currentCents: Int {
        let digitsOnly = amountText.filter(\.isNumber)
        return digitsOnly.isEmpty ? 0 : (Int(digitsOnly) ?? 0)
    }

    private func setCents(_ cents: Int) {
        let cents = max(0, cents)
        amountText = "\(cents / 100).\(String(format: "%02d", cents % 100))"
    }
}

#Preview {
    @Previewable @State var amountText = "12.50"
    CurrencyKeypadView(amountText: $amountText)
        .padding()
        .background(Color(.systemGroupedBackground))
}
