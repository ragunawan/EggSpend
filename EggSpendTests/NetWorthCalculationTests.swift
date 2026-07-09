import XCTest
import SwiftData
@testable import EggSpend

final class NetWorthCalculationTests: XCTestCase {
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

    func testTotalAssets() throws {
        insertAccounts([
            ("Checking", .checking, 5000),
            ("Savings", .savings, 10000),
            ("Investment", .investment, 25000)
        ])
        let accounts = try context.fetch(FetchDescriptor<Account>())
        XCTAssertEqual(NetWorthCalculator.totals(accounts: accounts).assets, 40000, accuracy: 0.001)
    }

    func testTotalLiabilities() throws {
        insertAccounts([
            ("Credit Card", .credit, -2000),
            ("Student Loan", .loan, -15000)
        ])
        let accounts = try context.fetch(FetchDescriptor<Account>())
        XCTAssertEqual(NetWorthCalculator.totals(accounts: accounts).liabilities, 17000, accuracy: 0.001)
    }

    func testNetWorthPositive() throws {
        insertAccounts([
            ("Savings", .savings, 50000),
            ("Loan", .loan, -10000)
        ])
        let accounts = try context.fetch(FetchDescriptor<Account>())
        XCTAssertEqual(NetWorthCalculator.current(accounts: accounts), 40000, accuracy: 0.001)
    }

    func testNetWorthNegative() throws {
        insertAccounts([
            ("Checking", .checking, 1000),
            ("Credit Card", .credit, -8000)
        ])
        let accounts = try context.fetch(FetchDescriptor<Account>())
        XCTAssertEqual(NetWorthCalculator.current(accounts: accounts), -7000, accuracy: 0.001)
    }

    func testExcludedLiabilityDoesNotReduceNetWorth() throws {
        let savings = Account(name: "Savings", type: .savings, balance: 20000)
        let mortgage = Account(name: "Mortgage", type: .loan, balance: -300000)
        mortgage.includeInNetWorth = false
        context.insert(savings)
        context.insert(mortgage)
        try context.save()

        let accounts = try context.fetch(FetchDescriptor<Account>())
        let totals = NetWorthCalculator.totals(accounts: accounts)
        XCTAssertEqual(NetWorthCalculator.current(accounts: accounts), 20000, accuracy: 0.001)
        XCTAssertEqual(totals.liabilities, 0, accuracy: 0.001)
    }

    func testIncludedAndExcludedLiabilitiesCalculateTogether() throws {
        let checking = Account(name: "Checking", type: .checking, balance: 5000)
        let creditCard = Account(name: "Credit Card", type: .credit, balance: -1200)
        let loan = Account(name: "Loan", type: .loan, balance: -10000)
        loan.includeInNetWorth = false
        context.insert(checking)
        context.insert(creditCard)
        context.insert(loan)
        try context.save()

        let accounts = try context.fetch(FetchDescriptor<Account>())
        XCTAssertEqual(NetWorthCalculator.current(accounts: accounts), 3800, accuracy: 0.001)
    }

    func testLiabilitiesIncludeInNetWorthByDefault() {
        let creditCard = Account(name: "Credit Card", type: .credit, balance: -500)

        XCTAssertTrue(creditCard.includeInNetWorth)
        XCTAssertTrue(creditCard.countsTowardNetWorth)
    }

    func testAccountTypeClassification() {
        XCTAssertTrue(AccountType.checking.isAsset)
        XCTAssertTrue(AccountType.savings.isAsset)
        XCTAssertTrue(AccountType.investment.isAsset)
        XCTAssertTrue(AccountType.other.isAsset)
        XCTAssertFalse(AccountType.credit.isAsset)
        XCTAssertFalse(AccountType.loan.isAsset)
    }

    func testAccountBalancePersistence() throws {
        let account = Account(name: "My Savings", type: .savings, balance: 12000)
        context.insert(account)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Account>())
        XCTAssertEqual(fetched.first?.balance ?? 0, 12000, accuracy: 0.001)
        XCTAssertEqual(fetched.first?.name, "My Savings")
    }

    func testAccountNotes() throws {
        let account = Account(name: "401k", type: .investment, balance: 80000, notes: "Employer match 4%")
        context.insert(account)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Account>())
        XCTAssertEqual(fetched.first?.notes, "Employer match 4%")
    }

    func testEmptyAccountsNetWorth() throws {
        XCTAssertEqual(NetWorthCalculator.current(accounts: []), 0)
        let totals = NetWorthCalculator.totals(accounts: [])
        XCTAssertEqual(totals.assets, 0)
        XCTAssertEqual(totals.liabilities, 0)
    }

    func testMixedAssetsAndLiabilitiesSubtractDebt() throws {
        insertAccounts([
            ("Checking", .checking, 25000),
            ("Savings", .savings, 50000),
            ("Credit Card", .credit, -1800),
            ("Car Loan", .loan, -24000)
        ])
        let accounts = try context.fetch(FetchDescriptor<Account>())
        XCTAssertEqual(NetWorthCalculator.current(accounts: accounts), 49200, accuracy: 0.001)
        let totals = NetWorthCalculator.totals(accounts: accounts)
        XCTAssertEqual(totals.assets, 75000, accuracy: 0.001)
        XCTAssertEqual(totals.liabilities, 25800, accuracy: 0.001)
        XCTAssertEqual(totals.assets - totals.liabilities,
                       NetWorthCalculator.current(accounts: accounts), accuracy: 0.001)
    }

    func testExcludedLiabilityLeftOutOfCurrentAndTotals() throws {
        let checking = Account(name: "Checking", type: .checking, balance: 10000)
        let loan = Account(name: "Loan", type: .loan, balance: -4000)
        loan.includeInNetWorth = false
        context.insert(checking)
        context.insert(loan)
        try context.save()

        let accounts = try context.fetch(FetchDescriptor<Account>())
        XCTAssertEqual(NetWorthCalculator.current(accounts: accounts), 10000, accuracy: 0.001)
        XCTAssertEqual(NetWorthCalculator.totals(accounts: accounts).liabilities, 0, accuracy: 0.001)
    }

    // Documents the invariant: assets always count — includeInNetWorth
    // only excludes liabilities (see Account.countsTowardNetWorth).
    func testAssetWithIncludeInNetWorthFalseStillCounts() throws {
        let savings = Account(name: "Savings", type: .savings, balance: 15000)
        savings.includeInNetWorth = false
        context.insert(savings)
        try context.save()

        let accounts = try context.fetch(FetchDescriptor<Account>())
        XCTAssertEqual(NetWorthCalculator.current(accounts: accounts), 15000, accuracy: 0.001)
        XCTAssertEqual(NetWorthCalculator.totals(accounts: accounts).assets, 15000, accuracy: 0.001)
    }

    func testAccountDeletion() throws {
        insertAccounts([
            ("Account A", .checking, 1000),
            ("Account B", .savings, 2000)
        ])
        var accounts = try context.fetch(FetchDescriptor<Account>())
        XCTAssertEqual(accounts.count, 2)

        context.delete(accounts[0])
        try context.save()

        accounts = try context.fetch(FetchDescriptor<Account>())
        XCTAssertEqual(accounts.count, 1)
    }

    func testArchivedAccountExcludedFromCurrentAndTotals() throws {
        let checking = Account(name: "Checking", type: .checking, balance: 5000)
        let oldSavings = Account(name: "Old Savings", type: .savings, balance: 20000)
        oldSavings.isArchived = true
        context.insert(checking)
        context.insert(oldSavings)
        try context.save()

        let accounts = try context.fetch(FetchDescriptor<Account>())
        XCTAssertEqual(NetWorthCalculator.current(accounts: accounts), 5000, accuracy: 0.001)
        let totals = NetWorthCalculator.totals(accounts: accounts)
        XCTAssertEqual(totals.assets, 5000, accuracy: 0.001)
    }

    func testArchivedLiabilityExcludedFromCurrentAndTotals() throws {
        let checking = Account(name: "Checking", type: .checking, balance: 5000)
        let oldCard = Account(name: "Old Card", type: .credit, balance: -1200)
        oldCard.isArchived = true
        context.insert(checking)
        context.insert(oldCard)
        try context.save()

        let accounts = try context.fetch(FetchDescriptor<Account>())
        XCTAssertEqual(NetWorthCalculator.current(accounts: accounts), 5000, accuracy: 0.001)
        XCTAssertEqual(NetWorthCalculator.totals(accounts: accounts).liabilities, 0, accuracy: 0.001)
    }

    func testUnarchivingAccountRestoresPreviousTotals() throws {
        let checking = Account(name: "Checking", type: .checking, balance: 5000)
        let savings = Account(name: "Savings", type: .savings, balance: 20000)
        context.insert(checking)
        context.insert(savings)
        try context.save()

        let accounts = try context.fetch(FetchDescriptor<Account>())
        let baseline = NetWorthCalculator.current(accounts: accounts)
        XCTAssertEqual(baseline, 25000, accuracy: 0.001)

        savings.isArchived = true
        try context.save()
        XCTAssertEqual(NetWorthCalculator.current(accounts: accounts), 5000, accuracy: 0.001)

        savings.isArchived = false
        try context.save()
        XCTAssertEqual(NetWorthCalculator.current(accounts: accounts), baseline, accuracy: 0.001)
    }

    func testAccountTypeIcons() {
        for type in AccountType.allCases {
            XCTAssertFalse(type.icon.isEmpty, "\(type.rawValue) should have an icon")
        }
    }

    private func insertAccounts(_ data: [(String, AccountType, Double)]) {
        for (name, type, balance) in data {
            context.insert(Account(name: name, type: type, balance: balance))
        }
        try? context.save()
    }
}
