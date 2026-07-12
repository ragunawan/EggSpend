import SwiftUI

struct SectionHeader: View {
    let title: LocalizedStringKey
    var trailingLabel: LocalizedStringKey?
    var trailingAction: (() -> Void)?

    init(
        _ title: LocalizedStringKey,
        trailing: (label: LocalizedStringKey, action: () -> Void)? = nil
    ) {
        self.title = title
        trailingLabel = trailing?.label
        trailingAction = trailing?.action
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(NestType.overline)
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(.secondary)

            Spacer()

            if let trailingLabel, let trailingAction {
                Button(action: trailingAction) {
                    HStack(spacing: Space.xs) {
                        Text(trailingLabel)
                        Image(systemName: "chevron.right")
                            .imageScale(.small)
                    }
                    .font(NestType.meta)
                }
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview("Section Headers") {
    VStack(spacing: Space.xl) {
        SectionHeader("Recent")
        SectionHeader("Goals & Budgets", trailing: ("See All", {}))
    }
    .padding(Space.lg)
}
