import SwiftUI

struct StatTile<Destination: View>: View {
    let label: LocalizedStringKey
    let value: Double
    var trend: LocalizedStringKey?
    var trendPositive: Bool?
    private let destination: (() -> Destination)?
    private let action: (() -> Void)?

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
        action = nil
    }

    var body: some View {
        Group {
            if let destination {
                NavigationLink(destination: destination) { content }
                    .buttonStyle(.plain)
            } else if let action {
                Button(action: action) { content }
                    .buttonStyle(.plain)
            } else {
                content
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
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
            } else {
                Text(" ")
                    .font(NestType.meta)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.sm)
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
        action = nil
    }

    init(
        label: LocalizedStringKey,
        value: Double,
        trend: LocalizedStringKey? = nil,
        trendPositive: Bool? = nil,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.value = value
        self.trend = trend
        self.trendPositive = trendPositive
        destination = nil
        self.action = action
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
