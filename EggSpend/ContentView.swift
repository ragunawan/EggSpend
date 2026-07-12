import SwiftUI

@Observable
final class TabRouter {
    var selectedTab: Int

    init(selectedTab: Int = TabRouter.initialTabFromLaunchArguments()) {
        self.selectedTab = selectedTab
    }

    private static func initialTabFromLaunchArguments() -> Int {
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "--tab"), args.count > idx + 1 {
            return Int(args[idx + 1]) ?? 0
        }
        return 0
    }
}

struct ContentView: View {
    @State private var tabRouter = TabRouter()

    var body: some View {
        @Bindable var tabRouter = tabRouter

        TabView(selection: $tabRouter.selectedTab) {
            DashboardView()
                .tabItem { Label("Home", systemImage: "bird.fill") }
                .tag(0)

            TransactionsListView()
                .tabItem { Label("Transactions", systemImage: "list.bullet.rectangle.fill") }
                .tag(1)

            BudgetView()
                .tabItem { Label("Budget", systemImage: "dollarsign.circle.fill") }
                .tag(2)

            NetWorthView()
                .tabItem { Label("Nest Egg", systemImage: "chart.pie.fill") }
                .tag(3)

            MetricsView()
                .tabItem { Label("Metrics", systemImage: "chart.bar.fill") }
                .tag(4)
        }
        .tint(.yolk)
        .environment(tabRouter)
    }
}

#Preview {
    ContentView()
        .modelContainer(PersistenceController.previewContainer())
}
