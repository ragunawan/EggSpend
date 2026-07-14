import SwiftUI

struct AmountLabel: View {
    let amount: Double
    let type: TransactionType
    var font: Font = .body

    private var color: Color { type == .income ? .positive : .negative }
    private var prefix: String { type == .income ? "+" : "-" }

    var body: some View {
        Text("\(prefix)\(amount, format: .currency(code: CurrencyFormat.code))")
            .font(font)
            .fontDesign(.rounded)
            .fontWeight(.semibold)
            .foregroundStyle(color)
    }
}

#Preview {
    VStack(spacing: 8) {
        AmountLabel(amount: 2500, type: .income)
        AmountLabel(amount: 45.99, type: .expense)
    }
    .padding()
}
