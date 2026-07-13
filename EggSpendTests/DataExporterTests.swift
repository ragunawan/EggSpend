import XCTest
import SwiftData
@testable import EggSpend

final class DataExporterTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        // Same 7-model schema as TransferTests.swift:9-20.
        let schema = Schema([Transaction.self, TransactionCategory.self, Account.self,
                             Budget.self, RecurringTransaction.self, SavingsGoal.self, Transfer.self, BalanceSnapshot.self, CategoryRule.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
    }

    // MARK: - Deterministic fixtures

    /// A local-noon date so the calendar day is stable across any reasonable
    /// system time zone (avoids flakiness from CSV day-boundary formatting).
    private func fixtureDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return Calendar.current.date(from: components)!
    }

    /// A whole-millisecond epoch instant, for JSON round-trip precision assertions.
    private func epochInstant(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    // MARK: - transactionsCSV

    func testTransactionsCSVRowCountMatchesInput() throws {
        let account = Account(name: "Checking", type: .checking, balance: 1000)
        let transactions = (0..<3).map { i in
            Transaction(title: "Tx \(i)", amount: 10, date: fixtureDate(2024, 3, 1 + i), type: .expense, account: account)
        }
        let csv = DataExporter.transactionsCSV(transactions)
        let (_, rows) = CSVParser.parse(csv)
        XCTAssertEqual(rows.count, 3)
    }

    func testTransactionsCSVRequiredHeadersPresent() {
        let csv = DataExporter.transactionsCSV([])
        let (headers, _) = CSVParser.parse(csv)
        XCTAssertEqual(headers, ["Date", "Description", "Amount", "Type", "Category", "Notes", "Account"])
    }

    func testTransactionsCSVDateFormatIsUnambiguousYYYYMMDD() {
        let date = fixtureDate(2024, 3, 5) // single-digit month/day exercises zero-padding
        let tx = Transaction(title: "Coffee", amount: 4.5, date: date, type: .expense)
        let csv = DataExporter.transactionsCSV([tx])
        let (headers, rows) = CSVParser.parse(csv)
        let dateIndex = headers.firstIndex(of: "Date")!
        let dateField = rows[0][dateIndex]

        // Independently reproduce the expected string using the same
        // locale/format contract (POSIX locale, system-default time zone)
        // documented on DataExporter.csvDateString.
        let expectedFormatter = DateFormatter()
        expectedFormatter.locale = Locale(identifier: "en_US_POSIX")
        expectedFormatter.dateFormat = "yyyy-MM-dd"
        XCTAssertEqual(dateField, expectedFormatter.string(from: date))
        XCTAssertTrue(dateField.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil)
    }

    func testTransactionsCSVAmountUsesDotDecimalRegardlessOfProcessLocale() {
        let income = Transaction(title: "Paycheck", amount: 1234.5, date: fixtureDate(2024, 3, 1), type: .income)
        let expense = Transaction(title: "Rent", amount: 42.5, date: fixtureDate(2024, 3, 1), type: .expense)
        let csv = DataExporter.transactionsCSV([income, expense])
        let (headers, rows) = CSVParser.parse(csv)
        let amountIndex = headers.firstIndex(of: "Amount")!

        // Locale-independent dot-decimal, 2 fraction digits, signed via signedAmount.
        XCTAssertEqual(rows[0][amountIndex], "1234.50")
        XCTAssertEqual(rows[1][amountIndex], "-42.50")
        XCTAssertFalse(rows[0][amountIndex].contains(","))
        XCTAssertFalse(rows[1][amountIndex].contains(","))
    }

    func testTransactionsCSVNilCategoryAndAccountProduceEmptyFields() {
        let tx = Transaction(title: "Cash purchase", amount: 5, date: fixtureDate(2024, 3, 1), type: .expense,
                              category: nil, account: nil)
        let csv = DataExporter.transactionsCSV([tx])
        let (headers, rows) = CSVParser.parse(csv)
        XCTAssertEqual(rows[0][headers.firstIndex(of: "Category")!], "")
        XCTAssertEqual(rows[0][headers.firstIndex(of: "Account")!], "")
    }

    func testTransactionsCSVEscapesEmbeddedCommaQuoteAndNewline() {
        let title = "Coffee, \"Iced\""
        let notes = "Line1\nLine2"
        let tx = Transaction(title: title, amount: 4.5, date: fixtureDate(2024, 3, 1), type: .expense, notes: notes)
        let csv = DataExporter.transactionsCSV([tx])
        let (headers, rows) = CSVParser.parse(csv)
        XCTAssertEqual(rows[0][headers.firstIndex(of: "Description")!], title)
        XCTAssertEqual(rows[0][headers.firstIndex(of: "Notes")!], notes)
    }

    // MARK: - transactionsCSV round trip

    func testTransactionsCSVRoundTripsThroughCSVParserSingleAccountFixture() throws {
        let account = Account(name: "Checking", type: .checking, balance: 1000)
        let groceries = TransactionCategory(name: "Groceries", icon: "cart", colorHex: "00FF00")
        context.insert(account)
        context.insert(groceries)

        let transactions = [
            Transaction(title: "Paycheck", amount: 1500, date: fixtureDate(2024, 3, 1), type: .income,
                        category: nil, account: account, notes: ""),
            Transaction(title: "Whole Foods", amount: 82.37, date: fixtureDate(2024, 3, 2), type: .expense,
                        category: groceries, account: account, notes: "Weekly shop"),
            Transaction(title: "Gym", amount: 40, date: fixtureDate(2024, 3, 3), type: .expense,
                        category: nil, account: account, notes: "")
        ]
        for tx in transactions { context.insert(tx) }

        let csv = DataExporter.transactionsCSV(transactions)
        let (headers, rows) = CSVParser.parse(csv)
        let mapping = ColumnMapping.autoDetectTransaction(headers: headers)
        let parsed = CSVParser.parseTransactionRows(rows: rows, headers: headers, mapping: mapping)

        XCTAssertEqual(parsed.count, transactions.count)
        XCTAssertTrue(parsed.allSatisfy(\.isValid))

        for (original, result) in zip(transactions, parsed) {
            XCTAssertEqual(result.title, original.title)
            XCTAssertEqual(result.amount ?? -1, original.amount, accuracy: 0.001)
            XCTAssertEqual(result.type, original.type)
            XCTAssertEqual(result.categoryName, original.category?.name)
            XCTAssertEqual(result.notes, original.notes)
            let day = try XCTUnwrap(result.date)
            XCTAssertTrue(Calendar.current.isDate(day, inSameDayAs: original.date))
        }
    }

    func testTransactionsCSVRoundTripDedupesFullyWhenSameAccountReselected() throws {
        let account = Account(name: "Checking", type: .checking, balance: 1000)
        context.insert(account)
        // Amounts are exactly representable in binary floating point (whole
        // numbers / halves) so the CSV string round trip can't introduce a
        // sub-cent floating-point drift that would break exact key equality
        // below — dedupe keys hash/compare Double exactly, not with a tolerance.
        let originals = [
            Transaction(title: "Paycheck", amount: 1500, date: fixtureDate(2024, 3, 1), type: .income, account: account),
            Transaction(title: "Whole Foods", amount: 82.5, date: fixtureDate(2024, 3, 2), type: .expense, account: account),
            Transaction(title: "Gym", amount: 40, date: fixtureDate(2024, 3, 3), type: .expense, account: account)
        ]
        for tx in originals { context.insert(tx) }
        try context.save()

        let csv = DataExporter.transactionsCSV(originals)
        let (headers, rows) = CSVParser.parse(csv)
        let mapping = ColumnMapping.autoDetectTransaction(headers: headers)
        let parsed = CSVParser.parseTransactionRows(rows: rows, headers: headers, mapping: mapping)

        // Mirrors CSVImportView.buildPreview(): existing persisted transactions
        // become the dedupe key set, keyed by their real account.
        let existingKeys = Set(originals.map {
            duplicateKey(date: $0.date, amount: $0.amount, title: $0.title, accountID: $0.account?.id)
        })
        let marked = markDuplicates(in: parsed, existingKeys: existingKeys, accountID: account.id)

        XCTAssertTrue(marked.allSatisfy(\.isDuplicate))
        XCTAssertTrue(marked.allSatisfy { !$0.willImport })
    }

    func testTransactionsCSVMultiAccountExportDoesNotFullyDedupeWithSingleAccountReimport() throws {
        // Structural limitation, documented as expected behavior: CSVImportView's
        // import flow applies ONE picker-chosen account to every row in a session
        // (see performImport()/buildPreview() — selectedImportAccount is a single
        // value, not per-row). A multi-account export re-imported with only one
        // account selected therefore builds dedupe keys against that one account
        // for every parsed row, while the *existing* keys reflect each
        // transaction's real (possibly different) account — so rows whose
        // original account isn't the one re-selected fail to match and are
        // treated as new, not duplicates.
        let checking = Account(name: "Checking", type: .checking, balance: 1000)
        let savings = Account(name: "Savings", type: .savings, balance: 500)
        context.insert(checking)
        context.insert(savings)
        let originals = [
            Transaction(title: "Paycheck", amount: 1500, date: fixtureDate(2024, 3, 1), type: .income, account: checking),
            Transaction(title: "Transfer In", amount: 200, date: fixtureDate(2024, 3, 2), type: .income, account: savings)
        ]
        for tx in originals { context.insert(tx) }
        try context.save()

        let csv = DataExporter.transactionsCSV(originals)
        let (headers, rows) = CSVParser.parse(csv)
        let mapping = ColumnMapping.autoDetectTransaction(headers: headers)
        let parsed = CSVParser.parseTransactionRows(rows: rows, headers: headers, mapping: mapping)

        let existingKeys = Set(originals.map {
            duplicateKey(date: $0.date, amount: $0.amount, title: $0.title, accountID: $0.account?.id)
        })
        // Re-import session where the user (re)selects only "Checking".
        let marked = markDuplicates(in: parsed, existingKeys: existingKeys, accountID: checking.id)

        XCTAssertFalse(marked.allSatisfy(\.isDuplicate))
        XCTAssertTrue(marked[0].isDuplicate)   // originally Checking — matches
        XCTAssertFalse(marked[1].isDuplicate)  // originally Savings — treated as new
    }

    // MARK: - exportFilename

    func testExportFilenameIsLocaleIndependentAndSlashFree() {
        let date = fixtureDate(2024, 3, 5)
        let filename = DataExporter.exportFilename(prefix: "Transactions", ext: "csv", date: date)
        XCTAssertEqual(filename, "EggSpend-Transactions-2024-03-05.csv")
        XCTAssertFalse(filename.contains("/"))
    }

    // MARK: - accountsCSV

    func testAccountsCSVRowCountAndHeaders() {
        let accounts = [
            Account(name: "Checking", type: .checking, balance: 1000),
            Account(name: "Visa", type: .credit, balance: -250.75)
        ]
        let csv = DataExporter.accountsCSV(accounts)
        let (headers, rows) = CSVParser.parse(csv)
        XCTAssertEqual(headers, ["Name", "Type", "Balance", "Notes"])
        XCTAssertEqual(rows.count, 2)
    }

    func testAccountsCSVRoundTripsThroughCSVParser() throws {
        let accounts = [
            Account(name: "Checking", type: .checking, balance: 1000, notes: "Primary"),
            Account(name: "Visa", type: .credit, balance: -250.75, notes: "")
        ]
        let csv = DataExporter.accountsCSV(accounts)
        let (headers, rows) = CSVParser.parse(csv)
        let mapping = ColumnMapping.autoDetectAccount(headers: headers)
        let parsed = CSVParser.parseAccountRows(rows: rows, headers: headers, mapping: mapping)

        XCTAssertEqual(parsed.count, accounts.count)
        XCTAssertTrue(parsed.allSatisfy(\.isValid))
        for (original, result) in zip(accounts, parsed) {
            XCTAssertEqual(result.name, original.name)
            XCTAssertEqual(result.type, original.type)
            XCTAssertEqual(result.balance ?? .nan, original.balance, accuracy: 0.001)
            XCTAssertEqual(result.notes, original.notes)
        }
    }

    // MARK: - transfersCSV

    func testTransfersCSVRowCountAndHeaders() {
        let checking = Account(name: "Checking", type: .checking, balance: 1000)
        let savings = Account(name: "Savings", type: .savings, balance: 500)
        let transfers = [Transfer(amount: 200, date: fixtureDate(2024, 3, 1), fromAccount: checking, toAccount: savings)]
        let csv = DataExporter.transfersCSV(transfers)
        let (headers, rows) = CSVParser.parse(csv)
        XCTAssertEqual(headers, ["Date", "From Account", "To Account", "Amount", "Notes"])
        XCTAssertEqual(rows.count, 1)
    }

    func testTransfersCSVNilFromOrToAccountProducesEmptyFields() {
        let savings = Account(name: "Savings", type: .savings, balance: 500)
        let transfer = Transfer(amount: 200, date: fixtureDate(2024, 3, 1), fromAccount: nil, toAccount: savings)
        let csv = DataExporter.transfersCSV([transfer])
        let (headers, rows) = CSVParser.parse(csv)
        XCTAssertEqual(rows[0][headers.firstIndex(of: "From Account")!], "")
        XCTAssertEqual(rows[0][headers.firstIndex(of: "To Account")!], "Savings")
    }

    // MARK: - fullBackupJSON

    /// A representative fixture touching all 7 models, with a mix of
    /// populated and nil optional relationships.
    private func makeRepresentativeFixture() -> (
        transactions: [Transaction], categories: [TransactionCategory], accounts: [Account],
        budgets: [Budget], recurring: [RecurringTransaction], goals: [SavingsGoal], transfers: [Transfer]
    ) {
        let checking = Account(name: "Checking", type: .checking, balance: 1000)
        let visa = Account(name: "Visa", type: .credit, balance: -250)
        checking.createdAt = epochInstant(1_700_000_000)
        checking.isDefaultChecking = true
        visa.createdAt = epochInstant(1_700_000_100)
        visa.dueDate = fixtureDate(2024, 4, 1)
        visa.annualPercentageRate = 21.99
        visa.minimumPayment = 25
        visa.plannedExtraPayment = 50

        let groceries = TransactionCategory(name: "Groceries", icon: "cart", colorHex: "00FF00", typeFilter: .expense, sortOrder: 1)

        let tx1 = Transaction(title: "Paycheck", amount: 1500, date: fixtureDate(2024, 3, 1), type: .income,
                              category: nil, account: checking, notes: "")
        tx1.createdAt = epochInstant(1_700_000_200)
        let tx2 = Transaction(title: "Whole Foods", amount: 82.37, date: fixtureDate(2024, 3, 2), type: .expense,
                              category: groceries, account: checking, notes: "Weekly shop",
                              recurringSourceID: UUID(), recurringDueDate: fixtureDate(2024, 3, 2), isAdjustment: false)
        tx2.createdAt = epochInstant(1_700_000_300)

        let budget = Budget(name: "Groceries budget", limitAmount: 400, period: .monthly, category: groceries, colorHex: "D4820A")
        budget.createdAt = epochInstant(1_700_000_400)
        budget.alertsEnabled = true
        budget.lastAlertedThreshold = .nearLimit
        budget.lastAlertedPeriodStart = fixtureDate(2024, 3, 1)
        tx2.budget = budget

        let recurring = RecurringTransaction(title: "Rent", amount: 1200, type: .expense, frequency: .monthly,
                                             startDate: fixtureDate(2024, 1, 1), category: nil, account: checking, notes: "")
        recurring.createdAt = epochInstant(1_700_000_500)
        recurring.endDate = fixtureDate(2025, 1, 1)
        recurring.reminderEnabled = true
        recurring.reminderDaysBefore = 3

        let goal = SavingsGoal(name: "Emergency fund", targetAmount: 5000, currentAmount: 0,
                               targetDate: fixtureDate(2024, 12, 31), linkedAccount: checking, notes: "6 months")
        goal.createdAt = epochInstant(1_700_000_600)

        let transfer = Transfer(amount: 300, date: fixtureDate(2024, 3, 5), fromAccount: checking, toAccount: nil, notes: "Cash withdrawal")
        transfer.createdAt = epochInstant(1_700_000_700)

        return (
            transactions: [tx1, tx2],
            categories: [groceries],
            accounts: [checking, visa],
            budgets: [budget],
            recurring: [recurring],
            goals: [goal],
            transfers: [transfer]
        )
    }

    func testFullBackupJSONIncludesAllSevenModelCollections() throws {
        let fixture = makeRepresentativeFixture()
        let data = try DataExporter.fullBackupJSON(
            transactions: fixture.transactions, categories: fixture.categories, accounts: fixture.accounts,
            budgets: fixture.budgets, recurringTransactions: fixture.recurring, savingsGoals: fixture.goals,
            transfers: fixture.transfers, exportDate: epochInstant(1_700_001_000),
            appVersion: "1.2.3", buildNumber: "42"
        )
        let envelope = try DataExporter.validateBackup(data)

        XCTAssertEqual(envelope.transactions.count, 2)
        XCTAssertEqual(envelope.categories.count, 1)
        XCTAssertEqual(envelope.accounts.count, 2)
        XCTAssertEqual(envelope.budgets.count, 1)
        XCTAssertEqual(envelope.recurringTransactions.count, 1)
        XCTAssertEqual(envelope.savingsGoals.count, 1)
        XCTAssertEqual(envelope.transfers.count, 1)
    }

    func testFullBackupJSONEnvelopeMetadataFields() throws {
        let exportDate = epochInstant(1_700_001_000.250)
        let data = try DataExporter.fullBackupJSON(
            transactions: [], categories: [], accounts: [], budgets: [], recurringTransactions: [],
            savingsGoals: [], transfers: [], exportDate: exportDate, appVersion: "1.2.3", buildNumber: "42"
        )
        let envelope = try DataExporter.validateBackup(data)

        XCTAssertEqual(envelope.schemaVersion, DataExporter.currentSchemaVersion)
        XCTAssertEqual(envelope.appVersion, "1.2.3")
        XCTAssertEqual(envelope.buildNumber, "42")
        XCTAssertEqual(envelope.exportDate, exportDate)
    }

    func testFullBackupJSONRoundTripsLosslesslyForRepresentativeFixture() throws {
        let fixture = makeRepresentativeFixture()
        let expectedTransactions = fixture.transactions.map(TransactionDTO.init)
        let expectedCategories = fixture.categories.map(TransactionCategoryDTO.init)
        let expectedAccounts = fixture.accounts.map(AccountDTO.init)
        let expectedBudgets = fixture.budgets.map(BudgetDTO.init)
        let expectedRecurring = fixture.recurring.map(RecurringTransactionDTO.init)
        let expectedGoals = fixture.goals.map(SavingsGoalDTO.init)
        let expectedTransfers = fixture.transfers.map(TransferDTO.init)

        let data = try DataExporter.fullBackupJSON(
            transactions: fixture.transactions, categories: fixture.categories, accounts: fixture.accounts,
            budgets: fixture.budgets, recurringTransactions: fixture.recurring, savingsGoals: fixture.goals,
            transfers: fixture.transfers, exportDate: epochInstant(1_700_001_000),
            appVersion: "1.2.3", buildNumber: "42"
        )
        let envelope = try DataExporter.validateBackup(data)

        XCTAssertEqual(envelope.transactions, expectedTransactions)
        XCTAssertEqual(envelope.categories, expectedCategories)
        XCTAssertEqual(envelope.accounts, expectedAccounts)
        XCTAssertEqual(envelope.budgets, expectedBudgets)
        XCTAssertEqual(envelope.recurringTransactions, expectedRecurring)
        XCTAssertEqual(envelope.savingsGoals, expectedGoals)
        XCTAssertEqual(envelope.transfers, expectedTransfers)

        // Spot-check a few individually significant fields that a naive
        // JSON strategy could silently corrupt: nested optional relationship
        // ids/names, an Int-backed enum (not stringified), and nil optionals.
        XCTAssertEqual(envelope.transactions[0].categoryID, nil)
        XCTAssertEqual(envelope.transactions[1].categoryID, fixture.categories[0].id)
        XCTAssertEqual(envelope.transactions[1].categoryName, "Groceries")
        XCTAssertEqual(envelope.transactions[1].budgetID, fixture.budgets[0].id)
        XCTAssertEqual(envelope.transactions[1].budgetName, "Groceries budget")
        XCTAssertEqual(envelope.accounts[0].isDefaultChecking, true)
        XCTAssertEqual(envelope.budgets[0].lastAlertedThreshold, 80)
        XCTAssertEqual(envelope.transfers[0].toAccountID, nil)
        XCTAssertEqual(envelope.transfers[0].fromAccountID, fixture.accounts[0].id)
        XCTAssertEqual(envelope.goals(for: fixture.goals[0].id)?.linkedAccountID, fixture.accounts[0].id)
    }

    func testFullBackupJSONRoundTripsForEmptyCollections() throws {
        let data = try DataExporter.fullBackupJSON(
            transactions: [], categories: [], accounts: [], budgets: [], recurringTransactions: [],
            savingsGoals: [], transfers: [], exportDate: epochInstant(1_700_001_000),
            appVersion: "1.2.3", buildNumber: "42"
        )
        let envelope = try DataExporter.validateBackup(data)

        XCTAssertTrue(envelope.transactions.isEmpty)
        XCTAssertTrue(envelope.categories.isEmpty)
        XCTAssertTrue(envelope.accounts.isEmpty)
        XCTAssertTrue(envelope.budgets.isEmpty)
        XCTAssertTrue(envelope.recurringTransactions.isEmpty)
        XCTAssertTrue(envelope.savingsGoals.isEmpty)
        XCTAssertTrue(envelope.transfers.isEmpty)
    }

    func testFullBackupJSONVersionCompatibilityCheckRejectsNewerSchemaVersion() throws {
        let data = try DataExporter.fullBackupJSON(
            transactions: [], categories: [], accounts: [], budgets: [], recurringTransactions: [],
            savingsGoals: [], transfers: [], exportDate: epochInstant(1_700_001_000),
            appVersion: "1.2.3", buildNumber: "42"
        )
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let futureVersion = DataExporter.currentSchemaVersion + 1
        json["schemaVersion"] = futureVersion
        let bumped = try JSONSerialization.data(withJSONObject: json)

        XCTAssertThrowsError(try DataExporter.validateBackup(bumped)) { error in
            guard case let DataExporterError.unsupportedSchemaVersion(found, supported) = error else {
                XCTFail("Expected DataExporterError.unsupportedSchemaVersion, got \(error)")
                return
            }
            XCTAssertEqual(found, futureVersion)
            XCTAssertEqual(supported, DataExporter.currentSchemaVersion)
        }
    }
}

private extension BackupEnvelope {
    func goals(for id: UUID) -> SavingsGoalDTO? {
        savingsGoals.first { $0.id == id }
    }
}
