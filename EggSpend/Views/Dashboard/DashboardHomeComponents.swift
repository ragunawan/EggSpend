import SwiftUI

struct SafeSpendHeroCard: View {
    let result: SafeSpendResult

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

            HStack(alignment: .firstTextBaseline) {
                Text(result.safeToSpendToday, format: .currency(code: CurrencyFormat.code))
                    .font(NestType.hero)
                    .foregroundStyle(statusColor)
                    .contentTransition(.numericText())
                Spacer()
                Label(statusLabel, systemImage: statusIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, Space.sm)
                    .padding(.vertical, Space.xs)
                    .background(statusColor.opacity(0.12), in: Capsule())
            }

            HStack {
                Text("Keeps \(result.requiredBuffer, format: .currency(code: CurrencyFormat.code)) cash buffer")
                Spacer()
                Text("Based on next 30 days")
            }
            .font(.caption2)
            .foregroundStyle(Color.textSecondaryWarm)
        }
        .padding(Space.sm)
        .nestCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Safe to Spend Today")
        .accessibilityValue("\(CurrencyFormat.money(result.safeToSpendToday)), \(statusLabel)")
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
