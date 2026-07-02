import SwiftUI

struct TransactionRowView: View {
    let transaction: Transaction
    var showsCardBackground: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            categoryIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.title)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 6) {
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
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background {
            if showsCardBackground {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: Color.nestBrown.opacity(0.07), radius: 5, y: 2)
            }
        }
    }

    private var categoryIcon: some View {
        ZStack {
            Circle()
                .fill((transaction.category?.color ?? (transaction.type == .income ? Color.green : Color.red)).opacity(0.15))
                .frame(width: 40, height: 40)
            Image(systemName: transaction.category?.icon ?? transaction.type.systemImage)
                .font(.system(size: 17))
                .foregroundStyle(transaction.category?.color ?? (transaction.type == .income ? .green : .red))
        }
    }
}
