import SwiftUI

struct DebtPayoffPlannerView: View {
    let account: Account

    @State private var aprText = ""
    @State private var paymentText = ""
    @State private var extraPaymentText = ""
    @State private var firstPaymentDate = Date.now
    @State private var propertyTaxText = ""
    @State private var insuranceText = ""
    @State private var pmiText = ""
    @State private var escrowText = ""
    @State private var expandedYears: Set<Int> = []
    @State private var hasPopulated = false

    private var result: DebtPayoffResult {
        DebtPayoffCalculator.calculate(
            balance: account.balance,
            annualPercentageRate: scenarioAPR,
            minimumPayment: scenarioPayment,
            extraPayment: scenarioExtraPayment
        )
    }

    private var amortizationSchedule: AmortizationSchedule {
        DebtPayoffCalculator.amortizationSchedule(
            balance: account.balance,
            annualPercentageRate: scenarioAPR,
            monthlyPayment: scenarioPayment,
            extraPayment: scenarioExtraPayment,
            firstPaymentDate: firstPaymentDate,
            monthlyEscrow: scenarioEscrow
        )
    }

    private var isMortgage: Bool { account.type == .mortgage }
    private var scenarioAPR: Double? { AmountParser.parse(aprText) }
    private var scenarioPayment: Double? { AmountParser.parse(paymentText) }
    private var scenarioExtraPayment: Double { AmountParser.parse(extraPaymentText) ?? 0 }
    private var scenarioEscrow: Double {
        [
            propertyTaxText,
            insuranceText,
            pmiText,
            escrowText
        ].reduce(0) { $0 + (AmountParser.parse($1) ?? 0) }
    }

    var body: some View {
        ZStack {
            NestBackground()

            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(account.name, systemImage: account.type.icon)
                            .font(.headline)
                            .foregroundStyle(Color.nestBrown)
                        Text(abs(account.balance), format: .currency(code: CurrencyFormat.code))
                            .font(NestType.hero)
                            .foregroundStyle(Color.negative)
                    }
                    .padding(.vertical, 6)
                }

                scenarioSection

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
                            .foregroundStyle(Color.negative)
                    case .projected:
                        valueRow("Months to payoff", "\(result.months)")
                        valueRow("Total interest", result.totalInterest.formatted(.currency(code: CurrencyFormat.code)))
                        if let payoffDate = result.payoffDate {
                            valueRow("Payoff date", payoffDate.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                }

                if isMortgage {
                    amortizationSection
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .navigationTitle("Payoff Planner")
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            guard !hasPopulated else { return }
            populateScenario()
            hasPopulated = true
        }
    }

    private var scenarioSection: some View {
        Section(
            header: Text(isMortgage ? "Mortgage Scenario" : "Payment Plan"),
            footer: Group {
                if isMortgage {
                    Text("Scenario changes are temporary and do not update the saved account.")
                }
            }
        ) {
            HStack {
                Text("APR")
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("0.00", text: $aprText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                Text("%")
                    .foregroundStyle(.secondary)
            }
            currencyField(isMortgage ? "Monthly P&I" : "Minimum payment", text: $paymentText)
            currencyField("Extra payment", text: $extraPaymentText)

            if isMortgage {
                DatePicker("First payment", selection: $firstPaymentDate, displayedComponents: .date)
                currencyField("Property tax", text: $propertyTaxText)
                currencyField("Insurance", text: $insuranceText)
                currencyField("PMI", text: $pmiText)
                currencyField("Other escrow", text: $escrowText)
                valueRow("Total escrow", scenarioEscrow.formatted(.currency(code: CurrencyFormat.code)))
            }
        }
    }

    private var amortizationSection: some View {
        Section("Amortization") {
            switch amortizationSchedule.status {
            case .paidOff:
                Label("This mortgage is already paid off.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.nestLeafGreen)
            case .missingInputs:
                Label("Add APR and monthly principal-and-interest payment to see the schedule.", systemImage: "info.circle")
                    .foregroundStyle(Color.twig)
            case .insufficientPayment:
                Label("Payment is too low to cover monthly interest.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.negative)
            case .projected:
                valueRow("Total interest", amortizationSchedule.totalInterest.formatted(.currency(code: CurrencyFormat.code)))
                if amortizationSchedule.totalEscrow > 0 {
                    valueRow("Total escrow", amortizationSchedule.totalEscrow.formatted(.currency(code: CurrencyFormat.code)))
                }
                if let payoffDate = amortizationSchedule.payoffDate {
                    valueRow("Final payment", payoffDate.formatted(date: .abbreviated, time: .omitted))
                }

                ForEach(amortizationSchedule.years) { year in
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedYears.contains(year.year) },
                            set: { isExpanded in
                                if isExpanded {
                                    expandedYears.insert(year.year)
                                } else {
                                    expandedYears.remove(year.year)
                                }
                            }
                        )
                    ) {
                        ForEach(year.payments) { payment in
                            paymentRow(payment)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(year.year))
                                .font(.headline)
                                .foregroundStyle(Color.nestBrown)
                            Text("Principal \(CurrencyFormat.money(year.principal)) · Interest \(CurrencyFormat.money(year.interest))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Ending balance \(CurrencyFormat.money(year.endingBalance))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
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

    private func currencyField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(CurrencyFormat.symbol)
                .foregroundStyle(.secondary)
            TextField("0.00", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }

    private func paymentRow(_ payment: AmortizationPayment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(payment.date.formatted(.dateTime.month(.abbreviated).year()))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(CurrencyFormat.money(payment.endingBalance))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.nestBrown)
            }
            HStack {
                metric("Payment", payment.payment)
                metric("Principal", payment.principal)
                metric("Interest", payment.interest)
            }
            if payment.escrow > 0 {
                Text("Escrow \(CurrencyFormat.money(payment.escrow))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func metric(_ label: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(CurrencyFormat.money(value))
                .font(.caption)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func populateScenario() {
        aprText = account.annualPercentageRate.map { $0.formatted(.number.precision(.fractionLength(2)).grouping(.never)) } ?? ""
        paymentText = account.minimumPayment.map { $0.formatted(.number.precision(.fractionLength(2)).grouping(.never)) } ?? ""
        extraPaymentText = account.plannedExtraPayment.map { $0.formatted(.number.precision(.fractionLength(2)).grouping(.never)) } ?? ""
        firstPaymentDate = account.mortgageFirstPaymentDate ?? account.dueDate ?? Date.now
        propertyTaxText = account.mortgageMonthlyPropertyTax.map { $0.formatted(.number.precision(.fractionLength(2)).grouping(.never)) } ?? ""
        insuranceText = account.mortgageMonthlyInsurance.map { $0.formatted(.number.precision(.fractionLength(2)).grouping(.never)) } ?? ""
        pmiText = account.mortgageMonthlyPMI.map { $0.formatted(.number.precision(.fractionLength(2)).grouping(.never)) } ?? ""
        escrowText = account.mortgageMonthlyEscrow.map { $0.formatted(.number.precision(.fractionLength(2)).grouping(.never)) } ?? ""
    }
}

#Preview {
    NavigationStack {
        let account = Account(name: "Mortgage", type: .mortgage, balance: -320_000)
        DebtPayoffPlannerView(account: account)
    }
}
