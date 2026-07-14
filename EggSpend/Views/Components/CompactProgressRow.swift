import SwiftUI

struct CompactProgressRow<Destination: View>: View {
    let name: String
    let leftAmount: Double
    let progress: Double
    let statusColor: Color
    private let destination: () -> Destination

    init(
        name: String,
        leftAmount: Double,
        progress: Double,
        statusColor: Color,
        @ViewBuilder destination: @escaping () -> Destination
    ) {
        self.name = name
        self.leftAmount = leftAmount
        self.progress = progress
        self.statusColor = statusColor
        self.destination = destination
    }

    private var progressAccessibilityValue: String {
        let percent = Int(progress * 100)
        let decisionAmount = CurrencyFormat.money(abs(leftAmount))
        if leftAmount < 0 || progress > 1 {
            return "\(nameText), \(decisionAmount) over, \(percent)% used, over budget"
        }
        return "\(nameText), \(decisionAmount) left, \(percent)% used"
    }

    private var nameText: String {
        name
    }

    var body: some View {
        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text(LocalizedStringKey(name))
                        .font(NestType.rowTitle.weight(.semibold))
                    Spacer()
                    Text(leftAmount < 0
                         ? "\(abs(leftAmount), format: .currency(code: CurrencyFormat.code)) over"
                         : "\(leftAmount, format: .currency(code: CurrencyFormat.code)) left")
                        .font(NestType.amount)
                        .foregroundStyle(statusColor)
                }
                ThinProgressBar(progress: progress, color: statusColor)
            }
            .padding(.vertical, Space.sm)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progressAccessibilityValue)
    }
}

#Preview("Compact Progress States") {
    NavigationStack {
        VStack(spacing: Space.md) {
            CompactProgressRow(name: "Groceries", leftAmount: 320, progress: 0.36, statusColor: .positive) { Text("Okay") }
            CompactProgressRow(name: "Dining", leftAmount: 40, progress: 0.86, statusColor: .warningTone) { Text("Warning") }
            CompactProgressRow(name: "Shopping", leftAmount: -75, progress: 1.18, statusColor: .negative) { Text("Over") }
        }
        .padding(Space.lg)
    }
}
