import Foundation
import SwiftData

enum TransactionEntryService {
    typealias BudgetAlertChecker = (ModelContext) -> Void

    @discardableResult
    static func createTransaction(
        title: String,
        amount: Double,
        date: Date,
        type: TransactionType,
        category: TransactionCategory?,
        account: Account?,
        budget: Budget? = nil,
        notes: String,
        context: ModelContext,
        budgetAlertChecker: BudgetAlertChecker = { BudgetAlertCoordinator.checkBudgets(context: $0) }
    ) -> Transaction {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let transaction = Transaction(
            title: trimmedTitle,
            amount: amount,
            date: date,
            type: type,
            category: category,
            account: account,
            budget: type == .expense ? budget : nil,
            notes: notes
        )
        context.insert(transaction)
        AccountBalanceService.apply(transaction, to: account)
        recordRuleIfNeeded(title: trimmedTitle, category: category, context: context)
        budgetAlertChecker(context)
        return transaction
    }

    static func updateTransaction(
        _ transaction: Transaction,
        title: String,
        amount: Double,
        date: Date,
        type: TransactionType,
        category: TransactionCategory?,
        account: Account?,
        budget: Budget? = nil,
        notes: String,
        context: ModelContext,
        budgetAlertChecker: BudgetAlertChecker = { BudgetAlertCoordinator.checkBudgets(context: $0) }
    ) {
        let oldAccount = transaction.account
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        AccountBalanceService.reverse(transaction, from: oldAccount)

        transaction.title = trimmedTitle
        transaction.amount = amount
        transaction.date = date
        transaction.type = type
        transaction.category = category
        transaction.account = account
        transaction.budget = type == .expense ? budget : nil
        transaction.notes = notes

        AccountBalanceService.apply(transaction, to: account)
        recordRuleIfNeeded(title: trimmedTitle, category: category, context: context)
        budgetAlertChecker(context)
    }

    @discardableResult
    static func createTransfer(
        amount: Double,
        date: Date,
        fromAccount: Account?,
        toAccount: Account?,
        savingsGoal: SavingsGoal? = nil,
        notes: String,
        context: ModelContext
    ) -> Transfer {
        let transfer = Transfer(
            amount: amount,
            date: date,
            fromAccount: fromAccount,
            toAccount: toAccount,
            savingsGoal: savingsGoal,
            notes: notes
        )
        context.insert(transfer)
        TransferBalanceService.apply(transfer)
        SavingsGoalContributionService.apply(transfer)
        return transfer
    }

    static func updateTransfer(
        _ transfer: Transfer,
        amount: Double,
        date: Date,
        fromAccount: Account?,
        toAccount: Account?,
        savingsGoal: SavingsGoal? = nil,
        notes: String
    ) {
        TransferBalanceService.reverse(transfer)
        SavingsGoalContributionService.reverse(transfer)
        transfer.amount = amount
        transfer.date = date
        transfer.fromAccount = fromAccount
        transfer.toAccount = toAccount
        transfer.savingsGoal = savingsGoal
        transfer.notes = notes
        TransferBalanceService.apply(transfer)
        SavingsGoalContributionService.apply(transfer)
    }

    // MARK: - Delete with undo snapshots
    //
    // Deletes return a value-type snapshot that can restore the deleted row
    // (used by the ledger's "Undo" toast). Snapshots hold relationship UUIDs,
    // not @Model references, so a category/account/budget deleted between the
    // delete and the undo simply resolves to nil on restore — the same
    // dangling-ID tolerance used by `BalanceSnapshot`/`CategoryRule`.

    struct DeletedTransaction {
        let id: UUID
        let title: String
        let amount: Double
        let date: Date
        let type: TransactionType
        let notes: String
        let createdAt: Date
        let isGenerated: Bool
        let recurringSourceID: UUID?
        let recurringDueDate: Date?
        let isAdjustment: Bool
        let categoryID: UUID?
        let accountID: UUID?
        let budgetID: UUID?

        init(from transaction: Transaction) {
            id = transaction.id
            title = transaction.title
            amount = transaction.amount
            date = transaction.date
            type = transaction.type
            notes = transaction.notes
            createdAt = transaction.createdAt
            isGenerated = transaction.isGenerated
            recurringSourceID = transaction.recurringSourceID
            recurringDueDate = transaction.recurringDueDate
            isAdjustment = transaction.isAdjustment
            categoryID = transaction.category?.id
            accountID = transaction.account?.id
            budgetID = transaction.budget?.id
        }
    }

    struct DeletedTransfer {
        let id: UUID
        let amount: Double
        let date: Date
        let notes: String
        let createdAt: Date
        let fromAccountID: UUID?
        let toAccountID: UUID?
        let savingsGoalID: UUID?

        init(from transfer: Transfer) {
            id = transfer.id
            amount = transfer.amount
            date = transfer.date
            notes = transfer.notes
            createdAt = transfer.createdAt
            fromAccountID = transfer.fromAccount?.id
            toAccountID = transfer.toAccount?.id
            savingsGoalID = transfer.savingsGoal?.id
        }
    }

    /// Reverses the account-balance effect and deletes the transaction,
    /// returning a snapshot suitable for `restoreTransaction`.
    @discardableResult
    static func deleteTransaction(_ transaction: Transaction, context: ModelContext) -> DeletedTransaction {
        let snapshot = DeletedTransaction(from: transaction)
        AccountBalanceService.reverse(transaction, from: transaction.account)
        context.delete(transaction)
        return snapshot
    }

    /// Re-inserts a deleted transaction from its snapshot, preserving its
    /// original `id`/`createdAt` (so cross-device duplicate sweeps and dedupe
    /// keys see the same row, not a new one) and re-applying the account
    /// balance. Does not re-record a category rule — restoring is not a fresh
    /// categorization signal.
    @discardableResult
    static func restoreTransaction(_ snapshot: DeletedTransaction, context: ModelContext) -> Transaction {
        let category = resolve(TransactionCategory.self, id: snapshot.categoryID, context: context) { $0.id }
        let account = resolve(Account.self, id: snapshot.accountID, context: context) { $0.id }
        let budget = resolve(Budget.self, id: snapshot.budgetID, context: context) { $0.id }
        let transaction = Transaction(
            title: snapshot.title,
            amount: snapshot.amount,
            date: snapshot.date,
            type: snapshot.type,
            category: category,
            account: account,
            budget: budget,
            notes: snapshot.notes,
            isGenerated: snapshot.isGenerated,
            recurringSourceID: snapshot.recurringSourceID,
            recurringDueDate: snapshot.recurringDueDate,
            isAdjustment: snapshot.isAdjustment
        )
        transaction.id = snapshot.id
        transaction.createdAt = snapshot.createdAt
        context.insert(transaction)
        AccountBalanceService.apply(transaction, to: account)
        return transaction
    }

    /// Reverses balance and savings-goal effects and deletes the transfer,
    /// returning a snapshot suitable for `restoreTransfer`.
    @discardableResult
    static func deleteTransfer(_ transfer: Transfer, context: ModelContext) -> DeletedTransfer {
        let snapshot = DeletedTransfer(from: transfer)
        TransferBalanceService.reverse(transfer)
        SavingsGoalContributionService.reverse(transfer)
        context.delete(transfer)
        return snapshot
    }

    /// Re-inserts a deleted transfer from its snapshot, preserving its
    /// original `id`/`createdAt` and re-applying balance and savings-goal
    /// contributions.
    @discardableResult
    static func restoreTransfer(_ snapshot: DeletedTransfer, context: ModelContext) -> Transfer {
        let fromAccount = resolve(Account.self, id: snapshot.fromAccountID, context: context) { $0.id }
        let toAccount = resolve(Account.self, id: snapshot.toAccountID, context: context) { $0.id }
        let goal = resolve(SavingsGoal.self, id: snapshot.savingsGoalID, context: context) { $0.id }
        let transfer = Transfer(
            amount: snapshot.amount,
            date: snapshot.date,
            fromAccount: fromAccount,
            toAccount: toAccount,
            savingsGoal: goal,
            notes: snapshot.notes
        )
        transfer.id = snapshot.id
        transfer.createdAt = snapshot.createdAt
        context.insert(transfer)
        TransferBalanceService.apply(transfer)
        SavingsGoalContributionService.apply(transfer)
        return transfer
    }

    /// Fetch-and-match by UUID. `#Predicate` can't capture a keypath closure,
    /// so this fetches the (small) table and filters in memory — consistent
    /// with the app's other dangling-ID-tolerant lookups.
    private static func resolve<T: PersistentModel>(
        _ modelType: T.Type,
        id: UUID?,
        context: ModelContext,
        idFor: (T) -> UUID
    ) -> T? {
        guard let id else { return nil }
        let rows = (try? context.fetch(FetchDescriptor<T>())) ?? []
        return rows.first { idFor($0) == id }
    }

    private static func recordRuleIfNeeded(
        title: String,
        category: TransactionCategory?,
        context: ModelContext
    ) {
        guard let category else { return }
        CategoryRuleEngine.recordRule(title: title, category: category, context: context)
    }
}
