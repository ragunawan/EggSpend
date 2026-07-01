import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Int = {
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "--tab"), args.count > idx + 1 {
            return Int(args[idx + 1]) ?? 0
        }
        return 0
    }()

    var body: some View {
        TabView(selection: $selectedTab) {
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
    }
}

#Preview {
    ContentView()
        .modelContainer(PersistenceController.previewContainer())
}
