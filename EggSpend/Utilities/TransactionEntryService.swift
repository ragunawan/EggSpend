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
        notes: String,
        context: ModelContext
    ) -> Transfer {
        let transfer = Transfer(
            amount: amount,
            date: date,
            fromAccount: fromAccount,
            toAccount: toAccount,
            notes: notes
        )
        context.insert(transfer)
        TransferBalanceService.apply(transfer)
        return transfer
    }

    static func updateTransfer(
        _ transfer: Transfer,
        amount: Double,
        date: Date,
        fromAccount: Account?,
        toAccount: Account?,
        notes: String
    ) {
        TransferBalanceService.reverse(transfer)
        transfer.amount = amount
        transfer.date = date
        transfer.fromAccount = fromAccount
        transfer.toAccount = toAccount
        transfer.notes = notes
        TransferBalanceService.apply(transfer)
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
