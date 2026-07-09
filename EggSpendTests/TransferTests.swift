import XCTest
import SwiftData
@testable import EggSpend

final class TransferTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([Transaction.self, TransactionCategory.self, Account.self,
                             Budget.self, RecurringTransaction.self, SavingsGoal.self, Transfer.self, BalanceSnapshot.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
    }

    // MARK: - Apply / reverse

    func testTransferDebitsFromAccountAndCreditsToAccount() throws {
        let checking = Account(name: "Checking", type: .checking, balance: 1000)
        let savings = Account(name: "Savings", type: .savings, balance: 500)
        let transfer = Transfer(amount: 200, fromAccount: checking, toAccount: savings)
        context.insert(checking)
        context.insert(savings)
        context.insert(transfer)

        TransferBalanceService.apply(transfer)

        XCTAssertEqual(checking.balance, 800, accuracy: 0.001)
        XCTAssertEqual(savings.balance, 700, accuracy: 0.001)
    }

    func testTransferReverseRestoresOriginalBalances() throws {
        let checking = Account(name: "Checking", type: .checking, balance: 1000)
        let savings = Account(name: "Savings", type: .savings, balance: 500)
        let transfer = Transfer(amount: 200, fromAccount: checking, toAccount: savings)
        context.insert(checking)
        context.insert(savings)
        context.insert(transfer)

        TransferBalanceService.apply(transfer)
        TransferBalanceService.reverse(transfer)

        XCTAssertEqual(checking.balance, 1000, accuracy: 0.001)
        XCTAssertEqual(savings.balance, 500, accuracy: 0.001)
    }

    // MARK: - Nil account no-ops

    func testTransferWithNilFromAccountOnlyCreditsToAccount() throws {
        let savings = Account(name: "Savings", type: .savings, balance: 500)
        let transfer = Transfer(amount: 200, fromAccount: nil, toAccount: savings)
        context.insert(savings)
        context.insert(transfer)

        TransferBalanceService.apply(transfer)

        XCTAssertEqual(savings.balance, 700, accuracy: 0.001)
    }

    func testTransferWithNilToAccountOnlyDebitsFromAccount() throws {
        let checking = Account(name: "Checking", type: .checking, balance: 1000)
        let transfer = Transfer(amount: 200, fromAccount: checking, toAccount: nil)
        context.insert(checking)
        context.insert(transfer)

        TransferBalanceService.apply(transfer)

        XCTAssertEqual(checking.balance, 800, accuracy: 0.001)
    }

    // MARK: - Asset/liability signs

    func testTransferBetweenAssetAndLiabilityAccounts() throws {
        // Paying down a credit card from checking: checking decreases,
        // credit card liability balance moves toward zero (increases).
        let checking = Account(name: "Checking", type: .checking, balance: 2000)
        let visa = Account(name: "Visa", type: .credit, balance: -500)
        let transfer = Transfer(amount: 300, fromAccount: checking, toAccount: visa)
        context.insert(checking)
        context.insert(visa)
        context.insert(transfer)

        TransferBalanceService.apply(transfer)

        XCTAssertEqual(checking.balance, 1700, accuracy: 0.001)
        XCTAssertEqual(visa.balance, -200, accuracy: 0.001)
    }

    // MARK: - Edit

    func testEditTransferChangingAmountUpdatesBothBalances() throws {
        let checking = Account(name: "Checking", type: .checking, balance: 1000)
        let savings = Account(name: "Savings", type: .savings, balance: 500)
        let transfer = Transfer(amount: 200, fromAccount: checking, toAccount: savings)
        context.insert(checking)
        context.insert(savings)
        context.insert(transfer)

        TransferBalanceService.apply(transfer)
        XCTAssertEqual(checking.balance, 800, accuracy: 0.001)
        XCTAssertEqual(savings.balance, 700, accuracy: 0.001)

        // Simulate edit: reverse old, update amount, apply new
        TransferBalanceService.reverse(transfer)
        transfer.amount = 400
        TransferBalanceService.apply(transfer)

        XCTAssertEqual(checking.balance, 600, accuracy: 0.001)
        XCTAssertEqual(savings.balance, 900, accuracy: 0.001)
    }

    func testEditTransferChangingAccountsUpdatesAllFourBalances() throws {
        let checking = Account(name: "Checking", type: .checking, balance: 1000)
        let savings = Account(name: "Savings", type: .savings, balance: 500)
        let newFrom = Account(name: "Cash", type: .other, balance: 300)
        let newTo = Account(name: "Roth IRA", type: .investment, balance: 5000)
        let transfer = Transfer(amount: 200, fromAccount: checking, toAccount: savings)
        context.insert(checking)
        context.insert(savings)
        context.insert(newFrom)
        context.insert(newTo)
        context.insert(transfer)

        TransferBalanceService.apply(transfer)
        XCTAssertEqual(checking.balance, 800, accuracy: 0.001)
        XCTAssertEqual(savings.balance, 700, accuracy: 0.001)

        // Simulate edit: reverse old accounts, change accounts, apply new
        TransferBalanceService.reverse(transfer)
        transfer.fromAccount = newFrom
        transfer.toAccount = newTo
        TransferBalanceService.apply(transfer)

        XCTAssertEqual(checking.balance, 1000, accuracy: 0.001) // restored
        XCTAssertEqual(savings.balance, 500, accuracy: 0.001)   // restored
        XCTAssertEqual(newFrom.balance, 100, accuracy: 0.001)   // debited
        XCTAssertEqual(newTo.balance, 5200, accuracy: 0.001)    // credited
    }

    // MARK: - Delete

    func testDeleteTransferReversesBothBalances() throws {
        let checking = Account(name: "Checking", type: .checking, balance: 1000)
        let savings = Account(name: "Savings", type: .savings, balance: 500)
        let transfer = Transfer(amount: 200, fromAccount: checking, toAccount: savings)
        context.insert(checking)
        context.insert(savings)
        context.insert(transfer)

        TransferBalanceService.apply(transfer)
        XCTAssertEqual(checking.balance, 800, accuracy: 0.001)
        XCTAssertEqual(savings.balance, 700, accuracy: 0.001)

        TransferBalanceService.reverse(transfer)
        context.delete(transfer)

        XCTAssertEqual(checking.balance, 1000, accuracy: 0.001)
        XCTAssertEqual(savings.balance, 500, accuracy: 0.001)
    }

    // MARK: - Persistence and relationships

    func testTransferPersistsAndFetches() throws {
        let checking = Account(name: "Checking", type: .checking, balance: 1000)
        let savings = Account(name: "Savings", type: .savings, balance: 500)
        let transfer = Transfer(amount: 200, fromAccount: checking, toAccount: savings, notes: "Monthly savings")
        context.insert(checking)
        context.insert(savings)
        context.insert(transfer)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Transfer>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.amount ?? 0, 200, accuracy: 0.001)
        XCTAssertEqual(fetched.first?.notes, "Monthly savings")
        XCTAssertEqual(fetched.first?.fromAccount?.name, "Checking")
        XCTAssertEqual(fetched.first?.toAccount?.name, "Savings")
    }

    func testAccountDeletionNullifiesTransferReferenceWithoutDeletingTransferHistory() throws {
        let checking = Account(name: "Checking", type: .checking, balance: 1000)
        let savings = Account(name: "Savings", type: .savings, balance: 500)
        let transfer = Transfer(amount: 200, fromAccount: checking, toAccount: savings)
        context.insert(checking)
        context.insert(savings)
        context.insert(transfer)
        try context.save()

        context.delete(checking)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Transfer>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertNil(fetched.first?.fromAccount)
        XCTAssertEqual(fetched.first?.toAccount?.name, "Savings")
    }
}
