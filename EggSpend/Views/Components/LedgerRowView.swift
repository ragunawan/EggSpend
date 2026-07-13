import SwiftUI

enum LedgerRow: Identifiable {
    case transaction(Transaction)
    case transfer(Transfer)
    case upcoming(RecurringOccurrence)
    case upcomingPayment(UpcomingPayment)

    var id: String {
        switch self {
        case .transaction(let transaction): "transaction-\(transaction.id.uuidString)"
        case .transfer(let transfer): "transfer-\(transfer.id.uuidString)"
        case .upcoming(let occurrence): "upcoming-\(occurrence.id)"
        case .upcomingPayment(let payment): "upcoming-payment-\(payment.id)"
        }
    }

    var date: Date {
        switch self {
        case .transaction(let transaction): transaction.date
        case .transfer(let transfer): transfer.date
        case .upcoming(let occurrence): occurrence.dueDate
        case .upcomingPayment(let payment): payment.dueDate
        }
    }

    var isUpcoming: Bool {
        if case .upcoming = self { return true }
        if case .upcomingPayment = self { return true }
        return false
    }
}

struct UpcomingPayment: Identifiable {
    let id: String
    let title: String
    let amount: Double
    let dueDate: Date
    let icon: String
    let iconColor: Color
    let account: Account?

    var accountName: String? { account?.name }
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
    var verticalPadding: CGFloat = Space.sm

    var body: some View {
        HStack(spacing: Space.md) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(iconColor)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.xs) {
                    Text(title)
                        .font(NestType.rowTitle)
                        .lineLimit(1)

                    if let titleAccountName {
                        Text(titleAccountName)
                            .font(NestType.meta)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, Space.xs)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.08), in: Capsule())
                    }
                }

                if !meta.isEmpty {
                    Text(meta.joined(separator: " · "))
                        .font(NestType.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            amount
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
        .padding(.vertical, verticalPadding)
        .padding(.horizontal, Space.md)
        .background {
            if style == .upcoming {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .inset(by: 1)
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
        case .upcomingPayment(let payment):
            AmountText(amount: payment.amount, type: .expense)
        }
    }

    private var title: String {
        switch row {
        case .transaction(let transaction): transaction.title
        case .transfer(let transfer): transferTitle(transfer)
        case .upcoming(let occurrence): occurrence.title
        case .upcomingPayment(let payment): payment.title
        }
    }

    private var titleAccountName: String? {
        guard showsMeta.contains(.account) else { return nil }

        switch row {
        case .transaction(let transaction):
            return transaction.account?.name
        case .upcoming(let occurrence):
            return occurrence.account?.name
        case .upcomingPayment(let payment):
            return payment.accountName
        case .transfer:
            return nil
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
        case .upcomingPayment(let payment):
            payment.icon
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
        case .upcomingPayment(let payment):
            payment.iconColor
        }
    }

    private var meta: [String] {
        switch row {
        case .transaction(let transaction):
            var values: [String] = []
            if showsMeta.contains(.category), let category = transaction.category {
                values.append(category.name)
            }
            if titleAccountName == nil, showsMeta.contains(.account), let account = transaction.account {
                values.append(account.name)
            }
            if showsMeta.contains(.date) {
                values.append(shortDateString(transaction.date))
            }
            return values
        case .transfer(let transfer):
            var values = [transferTitle(transfer)]
            if showsMeta.contains(.date) {
                values.append(shortDateString(transfer.date))
            }
            return values
        case .upcoming(let occurrence):
            var values = [String(localized: "Upcoming")]
            if showsMeta.contains(.category), let category = occurrence.category {
                values.append(category.name)
            }
            if titleAccountName == nil, showsMeta.contains(.account), let account = occurrence.account {
                values.append(account.name)
            }
            if showsMeta.contains(.date) {
                values.append(shortDateString(occurrence.dueDate))
            }
            return values
        case .upcomingPayment(let payment):
            var values = [String(localized: "Upcoming")]
            if titleAccountName == nil, showsMeta.contains(.account), let accountName = payment.accountName {
                values.append(accountName)
            }
            if showsMeta.contains(.date) {
                values.append(shortDateString(payment.dueDate))
            }
            return values
        }
    }

    private func shortDateString(_ date: Date) -> String {
        date.formatted(date: .numeric, time: .omitted)
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
    let payment = UpcomingPayment(
        id: "card",
        title: "Card payment",
        amount: 125,
        dueDate: .now,
        icon: "creditcard",
        iconColor: .info,
        account: Account(name: "Rewards Card", type: .credit, balance: 125)
    )

    VStack(spacing: Space.md) {
        LedgerRowView(row: .transaction(transaction))
        LedgerRowView(row: .transfer(transfer))
        LedgerRowView(row: .upcoming(occurrence), style: .upcoming)
        LedgerRowView(row: .upcomingPayment(payment), style: .upcoming)
    }
    .padding(Space.lg)
}
