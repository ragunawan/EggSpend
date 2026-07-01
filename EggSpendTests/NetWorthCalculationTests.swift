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
        let assets = accounts.filter(\.isAsset).reduce(0.0) { $0 + $1.balance }
        XCTAssertEqual(assets, 40000, accuracy: 0.001)
    }

    func testTotalLiabilities() throws {
        insertAccounts([
            ("Credit Card", .credit, -2000),
            ("Student Loan", .loan, -15000)
        ])
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let liabilities = accounts.filter { $0.isLiability && $0.includeInNetWorth }.reduce(0.0) { $0 + abs($1.balance) }
        XCTAssertEqual(liabilities, 17000, accuracy: 0.001)
    }

    func testNetWorthPositive() throws {
        insertAccounts([
            ("Savings", .savings, 50000),
            ("Loan", .loan, -10000)
        ])
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let assets = accounts.filter(\.isAsset).reduce(0.0) { $0 + $1.balance }
        let liabilities = accounts.filter { $0.isLiability && $0.includeInNetWorth }.reduce(0.0) { $0 + abs($1.balance) }
        XCTAssertEqual(assets - liabilities, 40000, accuracy: 0.001)
    }

    func testNetWorthNegative() throws {
        insertAccounts([
            ("Checking", .checking, 1000),
            ("Credit Card", .credit, -8000)
        ])
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let assets = accounts.filter(\.isAsset).reduce(0.0) { $0 + $1.balance }
        let liabilities = accounts.filter { $0.isLiability && $0.includeInNetWorth }.reduce(0.0) { $0 + abs($1.balance) }
        XCTAssertEqual(assets - liabilities, -7000, accuracy: 0.001)
    }

    func testExcludedLiabilityDoesNotReduceNetWorth() throws {
        let savings = Account(name: "Savings", type: .savings, balance: 20000)
        let mortgage = Account(name: "Mortgage", type: .loan, balance: -300000)
        mortgage.includeInNetWorth = false
        context.insert(savings)
        context.insert(mortgage)
        try context.save()

        let accounts = try context.fetch(FetchDescriptor<Account>())
        let assets = accounts.filter(\.isAsset).reduce(0.0) { $0 + $1.balance }
        let liabilities = accounts.filter { $0.isLiability && $0.includeInNetWorth }.reduce(0.0) { $0 + abs($1.balance) }

        XCTAssertEqual(assets - liabilities, 20000, accuracy: 0.001)
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
        let assets = accounts.filter(\.isAsset).reduce(0.0) { $0 + $1.balance }
        let liabilities = accounts.filter { $0.isLiability && $0.includeInNetWorth }.reduce(0.0) { $0 + abs($1.balance) }

        XCTAssertEqual(assets - liabilities, 3800, accuracy: 0.001)
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
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let netWorth = accounts.reduce(0.0) { total, account in
            guard account.countsTowardNetWorth else { return total }
            return total + (account.isAsset ? account.balance : -abs(account.balance))
        }
        XCTAssertEqual(netWorth, 0)
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
