import SwiftUI

struct EmptyStateView: View {
    enum Context {
        case listRow
        case stack
    }

    let title: LocalizedStringKey
    let icon: String
    let description: LocalizedStringKey
    var action: (label: LocalizedStringKey, handler: () -> Void)?
    var context: Context = .stack

    // A List row needs a single concrete height — `minHeight`/`maxHeight`
    // ranges (and `.fixedSize`) were tried and don't constrain
    // `ContentUnavailableView` inside a List row (confirmed by screenshot;
    // it still balloons to fill the scroll view). `ScaledMetric` keeps a
    // single, deterministic height while still growing with the user's
    // Dynamic Type setting, so the CTA button isn't clipped.
    @ScaledMetric(relativeTo: .body) private var listRowHeight: CGFloat = 340

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(title)
            } icon: {
                Image(systemName: icon).symbolEffect(.pulse)
            }
        } description: {
            Text(description)
        } actions: {
            if let action {
                Button(action: action.handler) {
                    Label(action.label, systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.nestBrown)
            }
        }
        .modifier(EmptyStateSizing(context: context, listRowHeight: listRowHeight))
    }
}

private struct EmptyStateSizing: ViewModifier {
    let context: EmptyStateView.Context
    let listRowHeight: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        switch context {
        case .listRow:
            content
                .frame(height: listRowHeight)
                // Cap Dynamic Type growth beyond AX3 — the fixed height budget
                // above was sized/settled for that ceiling (loop 26); letting text
                // keep scaling past it would clip the CTA button again.
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        case .stack:
            content
                // Unlike the List-row empty states, this sits in a plain VStack
                // inside a ScrollView, so a `minHeight` lets the card grow with
                // Dynamic Type instead of clipping — a fixed `.frame(height:)`
                // here was the B27 defect.
                .frame(minHeight: 140)
        }
    }
}

#Preview("Empty State Contexts") {
    VStack {
        EmptyStateView(
            title: "No Data Yet",
            icon: "chart.bar.xaxis",
            description: "Add your first transaction or account to see your metrics take shape.",
            action: ("Add Transaction", {}),
            context: .listRow
        )
        EmptyStateView(
            title: "Your nest is empty",
            icon: "bird",
            description: "Add your first transaction with the + button."
        )
    }
}
