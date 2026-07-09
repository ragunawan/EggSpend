import SwiftData
import Foundation

enum PersistenceController {
    static func seedDefaultCategoriesIfNeeded(modelContainer: ModelContainer) {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<TransactionCategory>()
        let existing = (try? context.fetch(descriptor)) ?? []
        guard existing.isEmpty else { return }

        let defaults: [(String, String, String, TransactionType?)] = [
            ("Food & Dining", "fork.knife", "E67E22", .expense),
            ("Shopping", "bag.fill", "9B59B6", .expense),
            ("Transport", "car.fill", "3498DB", .expense),
            ("Housing", "house.fill", "1ABC9C", .expense),
            ("Healthcare", "cross.fill", "E74C3C", .expense),
            ("Entertainment", "tv.fill", "F39C12", .expense),
            ("Education", "book.fill", "2980B9", .expense),
            ("Utilities", "bolt.fill", "7F8C8D", .expense),
            ("Travel", "airplane", "16A085", .expense),
            ("Salary", "briefcase.fill", "27AE60", .income),
            ("Freelance", "laptopcomputer", "2ECC71", .income),
            ("Investment Return", "chart.line.uptrend.xyaxis", "F1C40F", .income),
            ("Other", "ellipsis.circle.fill", "95A5A6", nil)
        ]

        for (index, (name, icon, color, typeFilter)) in defaults.enumerated() {
            let category = TransactionCategory(name: name, icon: icon, colorHex: color, typeFilter: typeFilter, sortOrder: index)
            context.insert(category)
        }

        do {
            try context.save()
        } catch {
            print("PersistenceController: failed to save default categories: \(error)")
        }
    }

    static func seedPreviewTransactionsIfNeeded(modelContainer: ModelContainer) {
        let context = ModelContext(modelContainer)
        let txDescriptor = FetchDescriptor<Transaction>()
        let existing = (try? context.fetch(txDescriptor)) ?? []
        guard existing.isEmpty else { return }

        let catDescriptor = FetchDescriptor<TransactionCategory>()
        let categories = (try? context.fetch(catDescriptor)) ?? []
        let food = categories.first { $0.name == "Food & Dining" }
        let salary = categories.first { $0.name == "Salary" }
        let transport = categories.first { $0.name == "Transport" }
        let entertainment = categories.first { $0.name == "Entertainment" }

        let calendar = Calendar.current
        let now = Date.now
        let sampleTransactions: [(String, Double, TransactionType, TransactionCategory?, String)] = [
            ("June Paycheck", 4200, .income, salary, "Direct deposit"),
            ("May Paycheck",  4200, .income, salary, ""),
            ("Whole Foods",    89.50, .expense, food, "Weekly groceries"),
            ("Blue Bottle Coffee", 6.75, .expense, food, "Morning latte"),
            ("Netflix", 17.99, .expense, entertainment, "Monthly subscription"),
            ("Uber",    14.50, .expense, transport, "Airport ride"),
            ("Dinner w/ friends", 52.00, .expense, food, "Thai restaurant on Mission"),
            ("BART",    4.70, .expense, transport, ""),
            ("Freelance project", 800, .income, nil, "Design work for client"),
            ("Lunch",  13.25, .expense, food, ""),
        ]

        for (i, (title, amount, type, category, notes)) in sampleTransactions.enumerated() {
            let date = calendar.date(byAdding: .day, value: -i * 2, to: now) ?? now
            let tx = Transaction(title: title, amount: amount, date: date,
                                 type: type, category: category, notes: notes)
            context.insert(tx)
        }

        let accounts: [(String, AccountType, Double)] = [
            ("Chase Checking",    .checking,   4_200),
            ("High Yield Savings",.savings,   18_500),
            ("Roth IRA",          .investment, 52_300),
            ("Chase Visa",        .credit,    -1_800),
            ("Student Loan",      .loan,     -24_000),
        ]
        for (name, type, balance) in accounts {
            context.insert(Account(name: name, type: type, balance: balance,
                                   notes: type == .investment ? "Vanguard target-date fund" : ""))
        }

        // Seed budgets (only if none exist yet)
        let budgetDescriptor = FetchDescriptor<Budget>()
        let existingBudgets = (try? context.fetch(budgetDescriptor)) ?? []
        if existingBudgets.isEmpty {
            let catDescriptor2 = FetchDescriptor<TransactionCategory>()
            let cats2 = (try? context.fetch(catDescriptor2)) ?? []
            let foodCat    = cats2.first { $0.name == "Food & Dining" }
            let transportCat = cats2.first { $0.name == "Transport" }
            let entCat     = cats2.first { $0.name == "Entertainment" }
            let shopCat    = cats2.first { $0.name == "Shopping" }

            let budgetDefs: [(String, Double, BudgetPeriod, TransactionCategory?, String)] = [
                ("Food & Dining",  500, .monthly, foodCat,    "E67E22"),
                ("Transport",      200, .monthly, transportCat,"3498DB"),
                ("Entertainment",  150, .monthly, entCat,     "9B59B6"),
                ("Shopping",       250, .monthly, shopCat,    "E74C3C"),
            ]
            for (name, limit, period, cat, hex) in budgetDefs {
                context.insert(Budget(name: name, limitAmount: limit, period: period,
                                      category: cat, colorHex: hex))
            }
        }

        do {
            try context.save()
        } catch {
            print("PersistenceController: failed to save seeded preview data: \(error)")
        }

        // Seed savings goals (only if none exist yet)
        let goalDescriptor = FetchDescriptor<SavingsGoal>()
        let existingGoals = (try? context.fetch(goalDescriptor)) ?? []
        if existingGoals.isEmpty {
            let accountDescriptor = FetchDescriptor<Account>()
            let savedAccounts = (try? context.fetch(accountDescriptor)) ?? []
            let savingsAccount = savedAccounts.first { $0.name == "High Yield Savings" }
            let calendar = Calendar.current

            context.insert(SavingsGoal(
                name: "Emergency Fund",
                targetAmount: 20_000,
                targetDate: calendar.date(byAdding: .month, value: 6, to: now),
                linkedAccount: savingsAccount,
                notes: "Six months of expenses, tracked against the high-yield savings account.",
                colorHex: "5BA4C1",
                icon: "umbrella.fill"
            ))
            context.insert(SavingsGoal(
                name: "Japan Trip",
                targetAmount: 4_500,
                currentAmount: 1_250,
                targetDate: calendar.date(byAdding: .month, value: 9, to: now),
                notes: "Flights + two weeks in Tokyo and Kyoto.",
                colorHex: "D4820A",
                icon: "airplane"
            ))
            context.insert(SavingsGoal(
                name: "New Laptop",
                targetAmount: 2_200,
                currentAmount: 2_200,
                notes: "",
                colorHex: "3D7A3B",
                icon: "laptopcomputer",
                status: .completed
            ))
        }

        do {
            try context.save()
        } catch {
            print("PersistenceController: failed to save seeded preview data: \(error)")
        }
    }

    static func previewContainer() -> ModelContainer {
        let schema = Schema([
            Transaction.self, TransactionCategory.self, Account.self,
            Budget.self, RecurringTransaction.self, SavingsGoal.self, Transfer.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        seedDefaultCategoriesIfNeeded(modelContainer: container)

        let descriptor = FetchDescriptor<TransactionCategory>()
        let categories = (try? context.fetch(descriptor)) ?? []
        let food = categories.first { $0.name == "Food & Dining" }
        let salary = categories.first { $0.name == "Salary" }

        let calendar = Calendar.current
        let now = Date.now
        for offset in 0..<30 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let isIncome = offset % 7 == 0
            let tx = Transaction(
                title: isIncome ? "Paycheck" : "Purchase \(offset)",
                amount: isIncome ? 2500 : Double.random(in: 10...200),
                date: date,
                type: isIncome ? .income : .expense,
                category: isIncome ? salary : food,
                notes: offset % 3 == 0 ? "Sample note for this transaction." : ""
            )
            context.insert(tx)
        }

        let accounts: [(String, AccountType, Double)] = [
            ("Chase Checking", .checking, 4_200),
            ("High Yield Savings", .savings, 15_000),
            ("Roth IRA", .investment, 48_500),
            ("Chase Visa", .credit, -1_200),
            ("Student Loan", .loan, -22_000)
        ]
        for (name, type, balance) in accounts {
            context.insert(Account(name: name, type: type, balance: balance))
        }

        do {
            try context.save()
        } catch {
            print("PersistenceController: failed to save seeded preview data: \(error)")
        }

        // Seed sample budgets
        let descriptor2 = FetchDescriptor<TransactionCategory>()
        let cats2 = (try? context.fetch(descriptor2)) ?? []
        let foodCat = cats2.first { $0.name == "Food & Dining" }
        let transportCat = cats2.first { $0.name == "Transport" }
        let entCat = cats2.first { $0.name == "Entertainment" }

        let budgets: [(String, Double, BudgetPeriod, TransactionCategory?, String)] = [
            ("Food & Dining", 500, .monthly, foodCat, "E67E22"),
            ("Transport",     200, .monthly, transportCat, "3498DB"),
            ("Entertainment", 150, .monthly, entCat, "9B59B6")
        ]
        for (name, limit, period, cat, hex) in budgets {
            context.insert(Budget(name: name, limitAmount: limit, period: period,
                                  category: cat, colorHex: hex))
        }

        // Seed sample recurring transactions
        let salaryCat = cats2.first { $0.name == "Salary" }
        let netflixCat = cats2.first { $0.name == "Entertainment" }
        let rentCat = cats2.first { $0.name == "Housing" }
        let accountDescriptor = FetchDescriptor<Account>()
        let savedAccounts = (try? context.fetch(accountDescriptor)) ?? []
        let checkingAccount = savedAccounts.first { $0.name == "Chase Checking" }

        let recurring: [(String, Double, TransactionType, RecurrenceFrequency, TransactionCategory?, Account?)] = [
            ("Salary Deposit", 4_200, .income,  .biweekly, salaryCat, checkingAccount),
            ("Netflix",         17.99, .expense, .monthly,  netflixCat, nil),
            ("Rent",         2_200,   .expense, .monthly,  rentCat, checkingAccount)
        ]
        let cal = Calendar.current
        for (title, amount, type, freq, cat, acct) in recurring {
            let start = cal.date(byAdding: .month, value: -1, to: .now) ?? .now
            let item = RecurringTransaction(title: title, amount: amount, type: type,
                                            frequency: freq, startDate: start, category: cat,
                                            account: acct)
            context.insert(item)
        }

        // Seed sample savings goals
        let savingsAccount = savedAccounts.first { $0.name == "High Yield Savings" }

        context.insert(SavingsGoal(
            name: "Emergency Fund",
            targetAmount: 20_000,
            targetDate: cal.date(byAdding: .month, value: 6, to: .now),
            linkedAccount: savingsAccount,
            notes: "Six months of expenses, tracked against the high-yield savings account.",
            colorHex: "5BA4C1",
            icon: "umbrella.fill"
        ))
        context.insert(SavingsGoal(
            name: "Japan Trip",
            targetAmount: 4_500,
            currentAmount: 1_250,
            targetDate: cal.date(byAdding: .month, value: 9, to: .now),
            notes: "Flights + two weeks in Tokyo and Kyoto.",
            colorHex: "D4820A",
            icon: "airplane"
        ))
        context.insert(SavingsGoal(
            name: "New Laptop",
            targetAmount: 2_200,
            currentAmount: 2_200,
            colorHex: "3D7A3B",
            icon: "laptopcomputer",
            status: .completed
        ))

        do {
            try context.save()
        } catch {
            print("PersistenceController: failed to save seeded preview data: \(error)")
        }
        return container
    }
}
