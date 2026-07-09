import XCTest
import SwiftData
@testable import EggSpend

final class TransactionAccountTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([Transaction.self, TransactionCategory.self, Account.self,
                             Budget.self, RecurringTransaction.self, SavingsGoal.self, Transfer.self])
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
}
