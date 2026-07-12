import SwiftUI

struct TransferRowView: View {
    let transfer: Transfer
    var showsCardBackground: Bool = true

    var body: some View {
        HStack(spacing: Space.md) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: Space.sm) {
                    Text("Transfer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(transfer.date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text(transfer.amount, format: .currency(code: CurrencyFormat.code))
                .font(.system(.callout, design: .rounded, weight: .medium))
                .foregroundStyle(Color.textSecondaryWarm)
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

    private var title: String {
        let from = transfer.fromAccount?.name ?? "Unknown"
        let to = transfer.toAccount?.name ?? "Unknown"
        return "\(from) → \(to)"
    }

    private var icon: some View {
        ZStack {
            Circle()
                .fill(Color.twig.opacity(0.15))
                .frame(width: 40, height: 40)
            Image(systemName: "arrow.left.arrow.right.circle.fill")
                .font(.body)
                .foregroundStyle(Color.textSecondaryWarm)
        }
    }
}
