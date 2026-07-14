import SwiftUI

struct AmountText: View {
    enum Sign {
        case positive
        case negative
        case neutral
    }

    enum Style {
        case hero
        case stat
        case row

        var font: Font {
            switch self {
            case .hero: NestType.hero
            case .stat: NestType.stat
            case .row: NestType.amount
            }
        }
    }

    let amount: Double
    let sign: Sign
    var style: Style = .row

    init(amount: Double, sign: Sign, style: Style = .row) {
        self.amount = sign == .neutral ? amount : abs(amount)
        self.sign = sign
        self.style = style
    }

    init(amount: Double, type: TransactionType, style: Style = .row) {
        self.init(
            amount: amount,
            sign: type == .income ? .positive : .negative,
            style: style
        )
    }

    private var prefix: String {
        switch sign {
        case .positive: "+"
        case .negative: "-"
        case .neutral: ""
        }
    }

    private var color: Color {
        switch sign {
        case .positive: .positive
        case .negative: .negative
        case .neutral: .primary
        }
    }

    private var accessibilityAmount: Double {
        switch sign {
        case .positive: amount
        case .negative: -amount
        case .neutral: amount
        }
    }

    var body: some View {
        Text("\(prefix)\(amount, format: .currency(code: CurrencyFormat.code))")
            .font(style.font)
            .foregroundStyle(color)
            .contentTransition(.numericText())
            .accessibilityLabel(CurrencyFormat.money(accessibilityAmount))
    }
}

#Preview("Amount Text Parity") {
    VStack(alignment: .leading, spacing: Space.lg) {
        HStack {
            AmountLabel(amount: 2_500, type: .income)
            AmountText(amount: 2_500, type: .income)
        }
        HStack {
            AmountLabel(amount: 45.99, type: .expense)
            AmountText(amount: 45.99, type: .expense)
        }
        AmountText(amount: 49_200, sign: .neutral, style: .hero)
    }
    .padding(Space.lg)
}
