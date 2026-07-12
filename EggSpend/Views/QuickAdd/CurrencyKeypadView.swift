import SwiftUI

struct CurrencyKeypadView: View {
    @Binding var amountText: String
    var locale: Locale = .current

    @ScaledMetric(relativeTo: .title3) private var keyHeight: CGFloat = 52

    private let rows = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["decimal", "0", "backspace"]
    ]

    private var decimalDisplay: String {
        locale.decimalSeparator.flatMap { $0.isEmpty ? nil : $0 } ?? "."
    }

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
        case "decimal":
            Text(decimalDisplay)
        case "backspace":
            Image(systemName: "delete.left")
                .accessibilityHidden(true)
        default:
            Text(key)
        }
    }

    private func accessibilityLabel(for key: String) -> Text {
        switch key {
        case "decimal": Text("Decimal separator")
        case "backspace": Text("Backspace")
        default: Text(key)
        }
    }

    private func handle(_ key: String) {
        switch key {
        case "backspace":
            guard !amountText.isEmpty else { return }
            amountText.removeLast()
        case "decimal":
            guard !amountText.contains(".") else { return }
            amountText = amountText.isEmpty ? "0." : amountText + "."
        default:
            appendDigit(key)
        }
    }

    private func appendDigit(_ digit: String) {
        guard digit.count == 1, digit.first?.isNumber == true else { return }
        if amountText == "0" {
            amountText = digit
        } else {
            amountText += digit
        }
    }
}

#Preview {
    @Previewable @State var amountText = "12.50"
    CurrencyKeypadView(amountText: $amountText)
        .padding()
        .background(Color(.systemGroupedBackground))
}
