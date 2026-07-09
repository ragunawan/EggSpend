import SwiftUI

struct TransferRowView: View {
    let transfer: Transfer
    var showsCardBackground: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 6) {
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
                .foregroundStyle(Color.twig)
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
                .font(.system(size: 17))
                .foregroundStyle(Color.twig)
        }
    }
}
