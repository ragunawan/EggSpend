import SwiftUI

enum LedgerRow: Identifiable {
    case transaction(Transaction)
    case transfer(Transfer)
    case upcoming(RecurringOccurrence)

    var id: String {
        switch self {
        case .transaction(let transaction): "transaction-\(transaction.id.uuidString)"
        case .transfer(let transfer): "transfer-\(transfer.id.uuidString)"
        case .upcoming(let occurrence): "upcoming-\(occurrence.id)"
        }
    }

    var date: Date {
        switch self {
        case .transaction(let transaction): transaction.date
        case .transfer(let transfer): transfer.date
        case .upcoming(let occurrence): occurrence.dueDate
        }
    }

    var isUpcoming: Bool {
        if case .upcoming = self { return true }
        return false
    }
}

struct LedgerRowView: View {
    enum MetaField: Hashable {
        case category
        case account
        case date
    }

    enum Style {
        case plain
        case upcoming
    }

    let row: LedgerRow
    var showsMeta: Set<MetaField> = [.category, .account, .date]
    var style: Style = .plain

    var body: some View {
        HStack(spacing: Space.md) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(iconColor)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title)
                    .font(NestType.rowTitle)
                    .lineLimit(1)

                if !meta.isEmpty {
                    Text(meta.joined(separator: " · "))
                        .font(NestType.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Space.sm)
            amount
        }
        .padding(.vertical, Space.sm)
        .padding(.horizontal, Space.md)
        .background {
            if style == .upcoming {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(
                        Color.info,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5, 4])
                    )
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var amount: some View {
        switch row {
        case .transaction(let transaction):
            AmountText(amount: transaction.amount, type: transaction.type)
        case .transfer(let transfer):
            AmountText(amount: transfer.amount, sign: .neutral)
        case .upcoming(let occurrence):
            AmountText(amount: occurrence.amount, type: occurrence.type)
        }
    }

    private var title: String {
        switch row {
        case .transaction(let transaction): transaction.title
        case .transfer(let transfer): transferTitle(transfer)
        case .upcoming(let occurrence): occurrence.title
        }
    }

    private var icon: String {
        switch row {
        case .transaction(let transaction):
            transaction.category?.icon ?? transaction.type.systemImage
        case .transfer:
            "arrow.left.arrow.right"
        case .upcoming(let occurrence):
            occurrence.category?.icon ?? occurrence.source.frequency.icon
        }
    }

    private var iconColor: Color {
        switch row {
        case .transaction(let transaction):
            transaction.category?.color ?? (transaction.type == .income ? .positive : .negative)
        case .transfer:
            .textSecondaryWarm
        case .upcoming(let occurrence):
            occurrence.category?.color ?? .info
        }
    }

    private var meta: [String] {
        switch row {
        case .transaction(let transaction):
            var values: [String] = []
            if showsMeta.contains(.category), let category = transaction.category {
                values.append(category.name)
            }
            if showsMeta.contains(.account), let account = transaction.account {
                values.append(account.name)
            }
            if showsMeta.contains(.date) {
                values.append(transaction.date.formatted(date: .abbreviated, time: .omitted))
            }
            return values
        case .transfer(let transfer):
            var values = [transferTitle(transfer)]
            if showsMeta.contains(.date) {
                values.append(transfer.date.formatted(date: .abbreviated, time: .omitted))
            }
            return values
        case .upcoming(let occurrence):
            var values = [String(localized: "Upcoming")]
            if showsMeta.contains(.category), let category = occurrence.category {
                values.append(category.name)
            }
            if showsMeta.contains(.account), let account = occurrence.account {
                values.append(account.name)
            }
            if showsMeta.contains(.date) {
                values.append(occurrence.dueDate.formatted(date: .abbreviated, time: .omitted))
            }
            return values
        }
    }

    private func transferTitle(_ transfer: Transfer) -> String {
        let from = transfer.fromAccount?.name ?? String(localized: "Unknown")
        let to = transfer.toAccount?.name ?? String(localized: "Unknown")
        return "\(from) → \(to)"
    }
}

#Preview("Ledger Row Variants") {
    let checking = Account(name: "Checking", type: .checking, balance: 2_000)
    let savings = Account(name: "Savings", type: .savings, balance: 5_000)
    let transaction = Transaction(title: "Coffee", amount: 6.75, type: .expense, account: checking)
    let transfer = Transfer(amount: 250, fromAccount: checking, toAccount: savings)
    let recurring = RecurringTransaction(title: "Rent", amount: 1_500, type: .expense, account: checking)
    let occurrence = RecurringOccurrence(id: "preview", source: recurring, dueDate: .now)

    VStack(spacing: Space.md) {
        LedgerRowView(row: .transaction(transaction))
        LedgerRowView(row: .transfer(transfer))
        LedgerRowView(row: .upcoming(occurrence), style: .upcoming)
    }
    .padding(Space.lg)
}
