import SwiftUI

struct TransactionRowView: View {
    let transaction: Transaction
    var showsCardBackground: Bool = true

    var body: some View {
        HStack(spacing: Space.md) {
            categoryIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.title)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: Space.sm) {
                    if let category = transaction.category {
                        CategoryBadgeView(category: category, compact: true)
                    }
                    if let account = transaction.account {
                        Label(account.name, systemImage: account.type.icon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 8)
            AmountLabel(amount: transaction.amount, type: transaction.type, font: .callout)
        }
        .padding(.vertical, Space.sm)
        .padding(.horizontal, Space.md)
        .background {
            if showsCardBackground {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(.regularMaterial)
            }
        }
    }

    private var categoryIcon: some View {
        ZStack {
            Circle()
                .fill((transaction.category?.color ?? (transaction.type == .income ? Color.positive : Color.negative)).opacity(0.15))
                .frame(width: 40, height: 40)
            Image(systemName: transaction.category?.icon ?? transaction.type.systemImage)
                .font(.body)
                .foregroundStyle(transaction.category?.color ?? (transaction.type == .income ? .positive : .negative))
        }
    }
}
