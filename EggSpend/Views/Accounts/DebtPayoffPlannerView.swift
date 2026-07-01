import SwiftUI

struct DebtPayoffPlannerView: View {
    let account: Account

    private var result: DebtPayoffResult {
        DebtPayoffCalculator.calculate(
            balance: account.balance,
            annualPercentageRate: account.annualPercentageRate,
            minimumPayment: account.minimumPayment,
            extraPayment: account.plannedExtraPayment ?? 0
        )
    }

    var body: some View {
        ZStack {
            AnimatedCanopyBackground()

            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(account.name, systemImage: account.type.icon)
                            .font(.headline)
                            .foregroundStyle(Color.nestBrown)
                        Text(abs(account.balance), format: .currency(code: "USD"))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.red)
                    }
                    .padding(.vertical, 6)
                }

                Section("Payment Plan") {
                    valueRow("APR", account.annualPercentageRate.map { String(format: "%.2f%%", $0) } ?? "Not set")
                    valueRow("Minimum payment", account.minimumPayment?.formatted(.currency(code: "USD")) ?? "Not set")
                    valueRow("Extra payment", (account.plannedExtraPayment ?? 0).formatted(.currency(code: "USD")))
                }

                Section("Estimate") {
                    switch result.status {
                    case .paidOff:
                        Label("This account is already paid off.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.nestLeafGreen)
                    case .missingInputs:
                        Label("Add APR and minimum payment to see a payoff estimate.", systemImage: "info.circle")
                            .foregroundStyle(Color.twig)
                    case .insufficientPayment:
                        Label("Payment is too low to cover monthly interest.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    case .projected:
                        valueRow("Months to payoff", "\(result.months)")
                        valueRow("Total interest", result.totalInterest.formatted(.currency(code: "USD")))
                        if let payoffDate = result.payoffDate {
                            valueRow("Payoff date", payoffDate.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .navigationTitle("Payoff Planner")
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func valueRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(Color.nestBrown)
        }
    }
}

#Preview {
    NavigationStack {
        DebtPayoffPlannerView(account: Account(name: "Credit Card", type: .credit, balance: -2500))
    }
}
