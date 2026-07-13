import XCTest
import SwiftData
@testable import EggSpend

final class TransactionAccountTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
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

    // MARK: - Asset account balance rules

    func testIncomeToAssetAccountIncreasesBalance() throws {
        let account = Account(name: "Checking", type: .checking, balance: 1000)
        let tx = Transaction(title: "Salary", amount: 500, type: .income)
        context.insert(account)
        context.insert(tx)

        AccountBalanceService.apply(tx, to: account)

        XCTAssertEqual(account.balance, 1500, accuracy: 0.001)
    }

    func testExpenseFromAssetAccountDecreasesBalance() throws {
        let account = Account(name: "Checking", type: .checking, balance: 1000)
        let tx = Transaction(title: "Groceries", amount: 100, type: .expense)
        context.insert(account)
        context.insert(tx)

        AccountBalanceService.apply(tx, to: account)

        XCTAssertEqual(account.balance, 900, accuracy: 0.001)
    }

    func testCheckingAccountCanStoreDefaultCheckingFlag() throws {
        let account = Account(name: "Primary Checking", type: .checking, balance: 1000)
        account.isDefaultChecking = true
        context.insert(account)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Account>())
        XCTAssertEqual(fetched.first?.type, .checking)
        XCTAssertEqual(fetched.first?.isDefaultChecking, true)
    }

    // MARK: - Liability account balance rules

    func testIncomeReducesLiabilityBalance() throws {
        // Credit card: balance stored as negative (–500 = $500 owed)
        let account = Account(name: "Visa", type: .credit, balance: -500)
        let tx = Transaction(title: "Payment", amount: 100, type: .income)
        context.insert(account)
        context.insert(tx)

        AccountBalanceService.apply(tx, to: account)

        // -500 + 100 = -400 (less owed)
        XCTAssertEqual(account.balance, -400, accuracy: 0.001)
    }

    func testExpenseIncreasesLiabilityBalance() throws {
        let account = Account(name: "Visa", type: .credit, balance: -500)
        let tx = Transaction(title: "Online Shopping", amount: 150, type: .expense)
        context.insert(account)
        context.insert(tx)

        AccountBalanceService.apply(tx, to: account)

        // -500 + (-150) = -650 (more owed)
        XCTAssertEqual(account.balance, -650, accuracy: 0.001)
    }

    // MARK: - Delete reversal

    func testDeleteTransactionReversesBalanceOnAssetAccount() throws {
        let account = Account(name: "Savings", type: .savings, balance: 2000)
        let tx = Transaction(title: "Bonus", amount: 500, type: .income)
        context.insert(account)
        context.insert(tx)

        AccountBalanceService.apply(tx, to: account)
        XCTAssertEqual(account.balance, 2500, accuracy: 0.001)

        AccountBalanceService.reverse(tx, from: account)
        XCTAssertEqual(account.balance, 2000, accuracy: 0.001)
    }

    func testDeleteTransactionReversesBalanceOnLiabilityAccount() throws {
        let account = Account(name: "Loan", type: .loan, balance: -10000)
        let tx = Transaction(title: "Monthly Payment", amount: 300, type: .income)
        context.insert(account)
        context.insert(tx)

        AccountBalanceService.apply(tx, to: account)
        XCTAssertEqual(account.balance, -9700, accuracy: 0.001)

        AccountBalanceService.reverse(tx, from: account)
        XCTAssertEqual(account.balance, -10000, accuracy: 0.001)
    }

    // MARK: - Edit: amount change

    func testEditTransactionAmountUpdatesBalance() throws {
        let account = Account(name: "Checking", type: .checking, balance: 1000)
        let tx = Transaction(title: "Freelance", amount: 300, type: .income)
        context.insert(account)
        context.insert(tx)

        AccountBalanceService.apply(tx, to: account)
        XCTAssertEqual(account.balance, 1300, accuracy: 0.001)

        // Simulate edit: reverse old, update amount, apply new
        AccountBalanceService.reverse(tx, from: account)
        tx.amount = 500
        AccountBalanceService.apply(tx, to: account)

        XCTAssertEqual(account.balance, 1500, accuracy: 0.001)
    }

    // MARK: - Edit: account change

    func testEditTransactionChangingAccountUpdatesBalances() throws {
        let oldAccount = Account(name: "Checking", type: .checking, balance: 1000)
        let newAccount = Account(name: "Savings", type: .savings, balance: 500)
        let tx = Transaction(title: "Transfer", amount: 200, type: .expense)
        context.insert(oldAccount)
        context.insert(newAccount)
        context.insert(tx)

        AccountBalanceService.apply(tx, to: oldAccount)
        XCTAssertEqual(oldAccount.balance, 800, accuracy: 0.001)

        // Simulate changing linked account
        AccountBalanceService.reverse(tx, from: oldAccount)
        tx.account = newAccount
        AccountBalanceService.apply(tx, to: newAccount)

        XCTAssertEqual(oldAccount.balance, 1000, accuracy: 0.001) // restored
        XCTAssertEqual(newAccount.balance, 300, accuracy: 0.001)  // applied
    }

    func testEditTransactionRemovingAccountReversesOldBalance() throws {
        let account = Account(name: "Checking", type: .checking, balance: 1000)
        let tx = Transaction(title: "Rent", amount: 800, type: .expense)
        context.insert(account)
        context.insert(tx)

        AccountBalanceService.apply(tx, to: account)
        XCTAssertEqual(account.balance, 200, accuracy: 0.001)

        // Simulate unlinking account (new account = nil)
        AccountBalanceService.reverse(tx, from: account)
        tx.account = nil
        AccountBalanceService.apply(tx, to: nil) // no-op

        XCTAssertEqual(account.balance, 1000, accuracy: 0.001) // restored
    }

    // MARK: - Account edit: balance adjustment

    func testEditAccountNameOnlyLeavesBalanceAndHistoryUntouched() throws {
        let account = Account(name: "Checking", type: .checking, balance: 4200)
        context.insert(account)

        let adjustment = AccountBalanceService.applyBalanceEdit(
            oldBalance: 4200, newBalance: 4200, to: account, context: context
        )

        XCTAssertNil(adjustment)
        XCTAssertEqual(account.balance, 4200, accuracy: 0.001)
        let fetched = try context.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(fetched.count, 0)
    }

    func testEditAccountBalanceCreatesAdjustmentTransactionYieldingNewBalance() throws {
        let account = Account(name: "Checking", type: .checking, balance: 4200)
        context.insert(account)

        let adjustment = AccountBalanceService.applyBalanceEdit(
            oldBalance: 4200, newBalance: 4000, to: account, context: context
        )

        let tx = try XCTUnwrap(adjustment)
        XCTAssertTrue(tx.isAdjustment)
        XCTAssertEqual(tx.type, .expense)
        XCTAssertEqual(tx.amount, 200, accuracy: 0.001)
        XCTAssertEqual(tx.title, "Balance adjustment")
        XCTAssertEqual(account.balance, 4000, accuracy: 0.001)
    }

    func testBalanceIncreaseCreatesIncomeTypedAdjustment() throws {
        let account = Account(name: "Savings", type: .savings, balance: 1000)
        context.insert(account)

        let adjustment = AccountBalanceService.applyBalanceEdit(
            oldBalance: 1000, newBalance: 1250, to: account, context: context
        )

        let tx = try XCTUnwrap(adjustment)
        XCTAssertTrue(tx.isAdjustment)
        XCTAssertEqual(tx.type, .income)
        XCTAssertEqual(tx.amount, 250, accuracy: 0.001)
        XCTAssertEqual(account.balance, 1250, accuracy: 0.001)
    }

    func testLiabilityBalanceEditCreatesIncomeTypedAdjustmentWhenOwedAmountDecreases() throws {
        // Credit card: balance stored as negative (-500 = $500 owed); paying down to -400
        // reduces what's owed, which is an income-typed adjustment (like a payment).
        let account = Account(name: "Visa", type: .credit, balance: -500)
        context.insert(account)

        let adjustment = AccountBalanceService.applyBalanceEdit(
            oldBalance: -500, newBalance: -400, to: account, context: context
        )

        let tx = try XCTUnwrap(adjustment)
        XCTAssertTrue(tx.isAdjustment)
        XCTAssertEqual(tx.type, .income)
        XCTAssertEqual(tx.amount, 100, accuracy: 0.001)
        XCTAssertEqual(account.balance, -400, accuracy: 0.001)
    }

    // MARK: - No-account transactions remain valid

    func testTransactionWithNoAccountIsValidAndPersists() throws {
        let tx = Transaction(title: "Cash Purchase", amount: 50, type: .expense)
        context.insert(tx)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertNil(fetched.first?.account)
    }

    func testNilAccountNoOpsOnApplyAndReverse() {
        let tx = Transaction(title: "Cash", amount: 20, type: .expense)
        // These should not crash or produce side effects
        AccountBalanceService.apply(tx, to: nil)
        AccountBalanceService.reverse(tx, from: nil)
    }

    // MARK: - Bill due date

    func testCreditAccountCanStoreAndFetchDueDate() throws {
        let account = Account(name: "Visa", type: .credit, balance: -500)
        let due = Date(timeIntervalSince1970: 1_800_000_000)
        account.dueDate = due
        context.insert(account)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Account>())
        XCTAssertEqual(fetched.first?.dueDate, due)
    }

    func testCheckingAccountDueDateDefaultsNil() throws {
        let account = Account(name: "Checking", type: .checking, balance: 1000)
        XCTAssertNil(account.dueDate)
    }

    func testLoanAccountDueDateDefaultsNilUntilSet() throws {
        let account = Account(name: "Loan", type: .loan, balance: -10000)
        XCTAssertNil(account.dueDate)
    }

    func testLiabilityDueDateRollsForwardToNextMonthWhenPast() throws {
        let calendar = Calendar(identifier: .gregorian)
        let account = Account(name: "Visa", type: .credit, balance: -500)
        account.dueDate = calendar.date(from: DateComponents(year: 2026, month: 6, day: 10))!
        let today = calendar.date(from: DateComponents(year: 2026, month: 7, day: 13))!

        XCTAssertTrue(account.rollDueDateIfNeeded(asOf: today, calendar: calendar))

        XCTAssertEqual(account.dueDate, calendar.date(from: DateComponents(year: 2026, month: 8, day: 10))!)
    }

    func testLiabilityDueDateDoesNotRollWhenTodayOrFuture() throws {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.date(from: DateComponents(year: 2026, month: 7, day: 13))!
        let account = Account(name: "Loan", type: .loan, balance: -10000)
        account.dueDate = today

        XCTAssertFalse(account.rollDueDateIfNeeded(asOf: today, calendar: calendar))
        XCTAssertEqual(account.dueDate, today)
    }

    func testAssetDueDateDoesNotRoll() throws {
        let calendar = Calendar(identifier: .gregorian)
        let account = Account(name: "Checking", type: .checking, balance: 1000)
        let oldDueDate = calendar.date(from: DateComponents(year: 2026, month: 6, day: 10))!
        account.dueDate = oldDueDate
        let today = calendar.date(from: DateComponents(year: 2026, month: 7, day: 13))!

        XCTAssertFalse(account.rollDueDateIfNeeded(asOf: today, calendar: calendar))
        XCTAssertEqual(account.dueDate, oldDueDate)
    }

    // MARK: - CSV import: net balance effect helper

    func testNetBalanceEffectSumsOnlyValidRowsWithSign() {
        let rows: [ParsedTransactionResult] = [
            // valid expense: -50
            ParsedTransactionResult(rowIndex: 0, title: "Coffee", date: .now, amount: 50, type: .expense, categoryName: nil, notes: ""),
            // valid income: +200
            ParsedTransactionResult(rowIndex: 1, title: "Refund", date: .now, amount: 200, type: .income, categoryName: nil, notes: ""),
            // invalid row (no date) should be excluded from the sum
            ParsedTransactionResult(rowIndex: 2, title: "Bad Row", date: nil, amount: 999, type: .expense, categoryName: nil, notes: ""),
        ]

        // Only the two valid rows count: -50 + 200 = 150
        XCTAssertEqual(netBalanceEffect(of: rows), 150, accuracy: 0.001)
    }

    // MARK: - CSV import: account balance application (acceptance criteria)

    func testImportingExpensesWithToggleOnReducesAccountBalance() throws {
        let account = Account(name: "Chase Checking", type: .checking, balance: 1000)
        context.insert(account)

        let expenses = [42.50, 18.25, 63.40]
        var transactions: [Transaction] = []
        for amount in expenses {
            let tx = Transaction(title: "Expense", amount: amount, type: .expense, account: account)
            context.insert(tx)
            transactions.append(tx)
            AccountBalanceService.apply(tx, to: account) // toggle ON
        }
        try context.save()

        let total = expenses.reduce(0, +)
        XCTAssertEqual(account.balance, 1000 - total, accuracy: 0.001)
        XCTAssertEqual(transactions.compactMap(\.account?.id), Array(repeating: account.id, count: 3))
    }

    func testImportingExpensesWithToggleOffLeavesBalanceUnchangedButLinksAccount() throws {
        let account = Account(name: "Chase Checking", type: .checking, balance: 1000)
        context.insert(account)

        let expenses = [42.50, 18.25, 63.40]
        var transactions: [Transaction] = []
        for amount in expenses {
            let tx = Transaction(title: "Expense", amount: amount, type: .expense, account: account)
            context.insert(tx)
            transactions.append(tx)
            // toggle OFF: AccountBalanceService.apply intentionally not called
        }
        try context.save()

        XCTAssertEqual(account.balance, 1000, accuracy: 0.001)
        for tx in transactions {
            XCTAssertEqual(tx.account?.id, account.id)
        }
    }

    // MARK: - CSV import: failure-path reversal symmetry

    func testReversingAllImportedTransactionsRestoresOriginalBalance() throws {
        let account = Account(name: "Chase Checking", type: .checking, balance: 1000)
        context.insert(account)
        let startingBalance = account.balance

        let expenses = [42.50, 18.25, 63.40]
        var transactions: [Transaction] = []
        for amount in expenses {
            let tx = Transaction(title: "Expense", amount: amount, type: .expense, account: account)
            context.insert(tx)
            transactions.append(tx)
            AccountBalanceService.apply(tx, to: account)
        }
        XCTAssertLessThan(account.balance, startingBalance)

        // Simulate the import catch-block rollback: reverse every applied transaction.
        for tx in transactions {
            AccountBalanceService.reverse(tx, from: account)
        }

        XCTAssertEqual(account.balance, startingBalance, accuracy: 0.001)
    }

    // MARK: - CSV import: duplicate detection

    func testMarkDuplicatesSkipsRowMatchingExistingTransaction() {
        let account = Account(name: "Checking", type: .checking, balance: 1000)
        context.insert(account)
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let existingKeys: Set<TransactionDuplicateKey> = [
            duplicateKey(date: day, amount: 42.50, title: "Coffee Shop", accountID: account.id)
        ]
        let rows = [
            ParsedTransactionResult(rowIndex: 0, title: "  COFFEE   Shop  ", date: day, amount: 42.50,
                                     type: .expense, categoryName: nil, notes: "")
        ]

        let marked = markDuplicates(in: rows, existingKeys: existingKeys, accountID: account.id)

        XCTAssertTrue(marked[0].isDuplicate)
        XCTAssertFalse(marked[0].willImport)
    }

    func testMarkDuplicatesCatchesWithinFileDuplicateOnSecondOccurrence() {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let rows = [
            ParsedTransactionResult(rowIndex: 0, title: "Coffee Shop", date: day, amount: 4.50,
                                     type: .expense, categoryName: nil, notes: ""),
            ParsedTransactionResult(rowIndex: 1, title: "Coffee Shop", date: day, amount: 4.50,
                                     type: .expense, categoryName: nil, notes: "")
        ]

        let marked = markDuplicates(in: rows, existingKeys: [], accountID: nil)

        XCTAssertFalse(marked[0].isDuplicate)
        XCTAssertTrue(marked[0].willImport)
        XCTAssertTrue(marked[1].isDuplicate)
        XCTAssertFalse(marked[1].willImport)
    }

    func testMarkDuplicatesTreatsDifferentDayAsDistinct() {
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let day2 = day1.addingTimeInterval(86_400)
        let existingKeys: Set<TransactionDuplicateKey> = [
            duplicateKey(date: day1, amount: 4.50, title: "Coffee Shop", accountID: nil)
        ]
        let rows = [
            ParsedTransactionResult(rowIndex: 0, title: "Coffee Shop", date: day2, amount: 4.50,
                                     type: .expense, categoryName: nil, notes: "")
        ]

        let marked = markDuplicates(in: rows, existingKeys: existingKeys, accountID: nil)

        XCTAssertFalse(marked[0].isDuplicate)
    }

    func testMarkDuplicatesTreatsDifferentAmountAsDistinct() {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let existingKeys: Set<TransactionDuplicateKey> = [
            duplicateKey(date: day, amount: 4.50, title: "Coffee Shop", accountID: nil)
        ]
        let rows = [
            ParsedTransactionResult(rowIndex: 0, title: "Coffee Shop", date: day, amount: 4.75,
                                     type: .expense, categoryName: nil, notes: "")
        ]

        let marked = markDuplicates(in: rows, existingKeys: existingKeys, accountID: nil)

        XCTAssertFalse(marked[0].isDuplicate)
    }

    func testMarkDuplicatesTreatsDifferentAccountAsDistinct() {
        let accountA = Account(name: "Checking", type: .checking, balance: 1000)
        let accountB = Account(name: "Savings", type: .savings, balance: 500)
        context.insert(accountA)
        context.insert(accountB)
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let existingKeys: Set<TransactionDuplicateKey> = [
            duplicateKey(date: day, amount: 4.50, title: "Coffee Shop", accountID: accountA.id)
        ]
        let rows = [
            ParsedTransactionResult(rowIndex: 0, title: "Coffee Shop", date: day, amount: 4.50,
                                     type: .expense, categoryName: nil, notes: "")
        ]

        let marked = markDuplicates(in: rows, existingKeys: existingKeys, accountID: accountB.id)

        XCTAssertFalse(marked[0].isDuplicate)
    }

    func testMarkDuplicatesLeavesStructurallyInvalidRowsUnmarked() {
        let existingKeys: Set<TransactionDuplicateKey> = []
        // Missing date makes this row structurally invalid; markDuplicates should pass it through untouched.
        let rows = [
            ParsedTransactionResult(rowIndex: 0, title: "Bad Row", date: nil, amount: 4.50,
                                     type: .expense, categoryName: nil, notes: "")
        ]

        let marked = markDuplicates(in: rows, existingKeys: existingKeys, accountID: nil)

        XCTAssertFalse(marked[0].isDuplicate)
        XCTAssertFalse(marked[0].isValid)
        XCTAssertFalse(marked[0].willImport)
    }

    func testNetBalanceEffectExcludesDuplicateRows() {
        var duplicateRow = ParsedTransactionResult(rowIndex: 0, title: "Coffee", date: .now, amount: 50,
                                                     type: .expense, categoryName: nil, notes: "")
        duplicateRow.isDuplicate = true
        let rows: [ParsedTransactionResult] = [
            duplicateRow,
            // valid, non-duplicate income: +200
            ParsedTransactionResult(rowIndex: 1, title: "Refund", date: .now, amount: 200, type: .income, categoryName: nil, notes: ""),
        ]

        // Duplicate row is excluded even though it's structurally valid: only +200 counts.
        XCTAssertEqual(netBalanceEffect(of: rows), 200, accuracy: 0.001)
    }
}
