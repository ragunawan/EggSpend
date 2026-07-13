import SwiftUI

struct SafeSpendHeroCard: View {
    let result: SafeSpendResult
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var statusLabel: String {
        switch result.status {
        case .onTrack: return "On track"
        case .tight: return "Tight today"
        case .pause: return "Pause spending"
        }
    }

    private var statusIcon: String {
        switch result.status {
        case .onTrack: return "checkmark.circle.fill"
        case .tight: return "exclamationmark.triangle.fill"
        case .pause: return "hand.raised.fill"
        }
    }

    private var statusColor: Color {
        switch result.status {
        case .onTrack: return .nestLeafGreen
        case .tight: return .yolk
        case .pause: return .negative
        }
    }

    var body: some View {
        VStack(spacing: Space.sm) {
            HStack {
                Label("Safe to Spend Today", systemImage: "leaf.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.nestBrown)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondaryWarm)
            }

            amountAndStatus

            footer
        }
        .padding(Space.sm)
        .nestCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Safe to Spend Today")
        .accessibilityValue("\(CurrencyFormat.money(result.safeToSpendToday)), \(statusLabel)")
    }

    @ViewBuilder
    private var amountAndStatus: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Space.xs) {
                amountText
                statusPill
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .firstTextBaseline) {
                amountText
                Spacer(minLength: Space.sm)
                statusPill
            }
        }
    }

    private var amountText: some View {
        Text(result.safeToSpendToday, format: .currency(code: CurrencyFormat.code))
            .font(NestType.hero)
            .foregroundStyle(statusColor)
            .contentTransition(.numericText())
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }

    private var statusPill: some View {
        Label(statusLabel, systemImage: statusIcon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(statusColor)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xs)
            .background(statusColor.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private var footer: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Keeps \(result.requiredBuffer, format: .currency(code: CurrencyFormat.code)) cash buffer")
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Based on next 30 days")
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.caption2)
            .foregroundStyle(Color.textSecondaryWarm)
        } else {
            HStack {
                Text("Keeps \(result.requiredBuffer, format: .currency(code: CurrencyFormat.code)) cash buffer")
                Spacer()
                Text("Based on next 30 days")
            }
            .font(.caption2)
            .foregroundStyle(Color.textSecondaryWarm)
        }
    }
}

struct InsightRow: View {
    let narrative: String?
    let deltas: [SpendingDeltaCalculator.CategoryDelta]

    var body: some View {
        NavigationLink(destination: MonthlyReviewView()) {
            HStack(alignment: .top, spacing: Space.sm) {
                Image(systemName: "arrow.up.arrow.down.circle.fill")
                    .font(.body)
                    .foregroundStyle(Color.eggBlue)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("What changed this month?")
                        .font(NestType.rowTitle.weight(.semibold))
                        .foregroundStyle(Color.nestBrown)

                    if let narrative {
                        Text(narrative)
                            .font(NestType.meta)
                            .foregroundStyle(Color.textSecondaryWarm)
                    } else {
                        ForEach(deltas) { delta in
                            Text(delta.sentence)
                                .font(NestType.meta)
                                .foregroundStyle(Color.textSecondaryWarm)
                        }
                    }
                }

                Spacer(minLength: Space.sm)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondaryWarm)
            }
            .padding(Space.sm)
            .nestCard()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

struct MoreLink<Destination: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let icon: String
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: Space.md) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(Color.eggBlue)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(title)
                        .font(NestType.rowTitle.weight(.semibold))
                        .foregroundStyle(Color.nestBrown)
                    Text(subtitle)
                        .font(NestType.meta)
                        .foregroundStyle(Color.textSecondaryWarm)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondaryWarm)
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
        }
        .buttonStyle(.plain)
    }
}
