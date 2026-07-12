import SwiftUI

struct StatTile<Destination: View>: View {
    let label: LocalizedStringKey
    let value: Double
    var trend: LocalizedStringKey?
    var trendPositive: Bool?
    private let destination: (() -> Destination)?

    init(
        label: LocalizedStringKey,
        value: Double,
        trend: LocalizedStringKey? = nil,
        trendPositive: Bool? = nil,
        @ViewBuilder destination: @escaping () -> Destination
    ) {
        self.label = label
        self.value = value
        self.trend = trend
        self.trendPositive = trendPositive
        self.destination = destination
    }

    var body: some View {
        Group {
            if let destination {
                NavigationLink(destination: destination) { content }
                    .buttonStyle(.plain)
            } else {
                content
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(label)
                .font(NestType.overline)
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(.secondary)

            AmountText(amount: value, sign: .neutral, style: .stat)

            if let trend {
                Text(trend)
                    .font(NestType.meta)
                    .foregroundStyle(trendColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.md)
        .nestCard()
    }

    private var trendColor: Color {
        switch trendPositive {
        case true: .positive
        case false: .negative
        case nil: .secondary
        }
    }
}

extension StatTile where Destination == EmptyView {
    init(
        label: LocalizedStringKey,
        value: Double,
        trend: LocalizedStringKey? = nil,
        trendPositive: Bool? = nil
    ) {
        self.label = label
        self.value = value
        self.trend = trend
        self.trendPositive = trendPositive
        destination = nil
    }
}

#Preview("Stat Tiles") {
    LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: Space.sm) {
        StatTile(label: "Flowed In", value: 4_200, trend: "Up 8%", trendPositive: true)
        StatTile(label: "Flowed Out", value: 1_350, trend: "Down 3%", trendPositive: true)
        StatTile(label: "Saved", value: 2_850)
        StatTile(label: "Net worth", value: 49_200) { Text("Nest Egg") }
    }
    .padding(Space.lg)
}
