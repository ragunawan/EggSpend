import Foundation

/// Exports app data as plain CSV (spreadsheet-friendly) or a versioned JSON
/// backup (full-fidelity, all 7 models). Pure data transformation only — no
/// UI, no file writing, no `ShareLink` wiring (that's a separate task).
enum DataExporter {

    // MARK: - Transactions CSV

    /// Headers: Date,Description,Amount,Type,Category,Notes,Account.
    /// The "Account" column is groundwork for a future account-aware import —
    /// `ColumnMapping.autoDetectTransaction` doesn't look for it today, and
    /// unknown headers are silently ignored by the auto-detector, so this
    /// stays forward-compatible with the current importer.
    static func transactionsCSV(_ transactions: [Transaction]) -> String {
        var rows: [[String]] = [["Date", "Description", "Amount", "Type", "Category", "Notes", "Account"]]
        for tx in transactions {
            rows.append([
                csvDateString(tx.date),
                tx.title,
                csvAmountString(tx.signedAmount),
                tx.type.rawValue,
                tx.category?.name ?? "",
                tx.notes,
                tx.account?.name ?? ""
            ])
        }
        return csvText(from: rows)
    }

    // MARK: - Accounts CSV

    /// Headers: Name,Type,Balance,Notes — matches `ColumnMapping.autoDetectAccount`.
    static func accountsCSV(_ accounts: [Account]) -> String {
        var rows: [[String]] = [["Name", "Type", "Balance", "Notes"]]
        for account in accounts {
            rows.append([
                account.name,
                account.type.rawValue,
                csvAmountString(account.balance),
                account.notes
            ])
        }
        return csvText(from: rows)
    }

    // MARK: - Transfers CSV

    /// Headers: Date,From Account,To Account,Amount,Notes. There's no domain
    /// parser for transfer CSVs (import doesn't support them yet) — this is
    /// human-readable and tokenizer-parseable groundwork, not a round-trip
    /// contract with an existing importer.
    static func transfersCSV(_ transfers: [Transfer]) -> String {
        var rows: [[String]] = [["Date", "From Account", "To Account", "Amount", "Notes"]]
        for transfer in transfers {
            rows.append([
                csvDateString(transfer.date),
                transfer.fromAccount?.name ?? "",
                transfer.toAccount?.name ?? "",
                csvAmountString(transfer.amount),
                transfer.notes
            ])
        }
        return csvText(from: rows)
    }

    // MARK: - Export filenames

    /// Builds `"EggSpend-<prefix>-yyyy-MM-dd.<ext>"`, e.g.
    /// `"EggSpend-Transactions-2026-07-09.csv"`. Uses the same
    /// `en_US_POSIX` yyyy-MM-dd pattern as `csvDateString` deliberately: a
    /// locale-current formatter can render the date with a "/" separator
    /// (a path separator) for some calendars/locales, which would corrupt
    /// the filename.
    static func exportFilename(prefix: String, ext: String, date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "EggSpend-\(prefix)-\(formatter.string(from: date)).\(ext)"
    }

    // MARK: - CSV formatting helpers

    /// yyyy-MM-dd, locale-independent (`en_US_POSIX`). Time zone is
    /// intentionally left at the system default rather than forced to UTC:
    /// `CSVParser.parseDate` and the import dedupe key's
    /// `Calendar.current.startOfDay` both operate in local time, so forcing
    /// UTC here would risk an off-by-one-day mismatch for transactions near
    /// midnight.
    private static func csvDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Locale-independent dot-decimal amount string (2 fraction digits, no
    /// grouping separator). NEVER use `.formatted()`/locale-current
    /// formatting for exported money fields — under many locales that emits
    /// a comma decimal mark, which other tools (and our own `CSVParser`,
    /// which is dot-decimal only per `parseAmount`) can't reliably re-parse.
    private static func csvAmountString(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.decimalSeparator = "."
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    /// RFC-4180 quoting: a field is quoted when it contains a comma, quote,
    /// or newline; embedded quotes are escaped by doubling. Rows are joined
    /// with LF (CSVParser accepts both LF and CRLF line endings).
    ///
    /// Note: `CSVParser`'s row scanner trims whitespace from every field,
    /// including inside quoted fields (CSVParser.swift:47,50), so a field
    /// with leading/trailing spaces loses that padding on re-import. That's
    /// a pre-existing parser characteristic, not an exporter bug.
    private static func csvText(from rows: [[String]]) -> String {
        rows.map { row in row.map(csvField).joined(separator: ",") }
            .joined(separator: "\n")
    }

    private static func csvField(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - Full JSON backup

    /// Current schema version for `fullBackupJSON`'s output. Bump this (and
    /// teach `validateBackup` / a future restore path about the delta) any
    /// time `BackupEnvelope` or a DTO's shape changes.
    static let currentSchemaVersion = 3

    /// Builds a full, versioned JSON backup of all 7 persistent models.
    /// `appVersion`/`buildNumber` default to `Bundle.main`'s Info.plist
    /// values (with an "unknown" fallback) but are injectable so callers
    /// (and tests) can pin them deterministically.
    static func fullBackupJSON(
        transactions: [Transaction],
        categories: [TransactionCategory],
        accounts: [Account],
        budgets: [Budget],
        recurringTransactions: [RecurringTransaction],
        savingsGoals: [SavingsGoal],
        transfers: [Transfer],
        exportDate: Date = .now,
        appVersion: String = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown",
        buildNumber: String = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "unknown"
    ) throws -> Data {
        let envelope = BackupEnvelope(
            schemaVersion: currentSchemaVersion,
            exportDate: exportDate,
            appVersion: appVersion,
            buildNumber: buildNumber,
            transactions: transactions.map(TransactionDTO.init),
            categories: categories.map(TransactionCategoryDTO.init),
            accounts: accounts.map(AccountDTO.init),
            budgets: budgets.map(BudgetDTO.init),
            recurringTransactions: recurringTransactions.map(RecurringTransactionDTO.init),
            savingsGoals: savingsGoals.map(SavingsGoalDTO.init),
            transfers: transfers.map(TransferDTO.init)
        )
        return try jsonEncoder().encode(envelope)
    }

    /// Decodes `data` as a `BackupEnvelope` and rejects backups whose
    /// `schemaVersion` is newer than this build understands. This is
    /// import-validation groundwork only — actually restoring a backup into
    /// the store is out of scope for this task.
    static func validateBackup(_ data: Data) throws -> BackupEnvelope {
        let envelope = try jsonDecoder().decode(BackupEnvelope.self, from: data)
        guard envelope.schemaVersion <= currentSchemaVersion else {
            throw DataExporterError.unsupportedSchemaVersion(
                found: envelope.schemaVersion,
                supported: currentSchemaVersion
            )
        }
        return envelope
    }

    // MARK: - JSON encoding/decoding helpers

    /// ISO 8601 with fractional seconds, on both encode and decode. The
    /// default `.iso8601` strategy truncates to whole seconds, which breaks
    /// exact round-tripping of `Date` fields like `createdAt`. A fresh
    /// `ISO8601DateFormatter` is created per call (rather than shared) so
    /// this closure stays free of captured non-Sendable state under Swift 6
    /// strict concurrency.
    private static func jsonEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }

    private static func jsonDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = formatter.date(from: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected ISO 8601 date with fractional seconds, got \"\(raw)\""
                )
            }
            return date
        }
        return decoder
    }
}

// MARK: - Errors

enum DataExporterError: Error, LocalizedError {
    case unsupportedSchemaVersion(found: Int, supported: Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let found, let supported):
            return "This backup (schema \(found)) was created by a newer version of EggSpend than this app supports (schema \(supported)). Update the app to restore it."
        }
    }
}

// MARK: - Backup envelope

/// Top-level container for a full JSON backup. `schemaVersion` gates
/// forward-compatibility via `DataExporter.validateBackup`.
struct BackupEnvelope: Codable, Equatable {
    var schemaVersion: Int
    var exportDate: Date
    var appVersion: String
    var buildNumber: String
    var transactions: [TransactionDTO]
    var categories: [TransactionCategoryDTO]
    var accounts: [AccountDTO]
    var budgets: [BudgetDTO]
    var recurringTransactions: [RecurringTransactionDTO]
    var savingsGoals: [SavingsGoalDTO]
    var transfers: [TransferDTO]
}

// MARK: - DTOs
//
// Each DTO denormalizes relationships as an id (to restore links by identity)
// plus a human-readable name (so the JSON is inspectable without cross-
// referencing ids). Enum fields are stored as their model's rawValue.

struct TransactionDTO: Codable, Equatable {
    var id: UUID
    var title: String
    var amount: Double
    var date: Date
    var type: String
    var notes: String
    var createdAt: Date
    var isGenerated: Bool
    var recurringSourceID: UUID?
    var recurringDueDate: Date?
    var isAdjustment: Bool
    var categoryID: UUID?
    var categoryName: String?
    var accountID: UUID?
    var accountName: String?
    var budgetID: UUID?
    var budgetName: String?

    init(_ transaction: Transaction) {
        id = transaction.id
        title = transaction.title
        amount = transaction.amount
        date = transaction.date
        type = transaction.typeRaw
        notes = transaction.notes
        createdAt = transaction.createdAt
        isGenerated = transaction.isGenerated
        recurringSourceID = transaction.recurringSourceID
        recurringDueDate = transaction.recurringDueDate
        isAdjustment = transaction.isAdjustment
        categoryID = transaction.category?.id
        categoryName = transaction.category?.name
        accountID = transaction.account?.id
        accountName = transaction.account?.name
        budgetID = transaction.budget?.id
        budgetName = transaction.budget?.name
    }
}

struct TransactionCategoryDTO: Codable, Equatable {
    var id: UUID
    var name: String
    var icon: String
    var colorHex: String
    var typeFilter: String?
    var isArchived: Bool
    var sortOrder: Int

    init(_ category: TransactionCategory) {
        id = category.id
        name = category.name
        icon = category.icon
        colorHex = category.colorHex
        typeFilter = category.typeFilter
        isArchived = category.isArchived
        sortOrder = category.sortOrder
    }
}

struct AccountDTO: Codable, Equatable {
    var id: UUID
    var name: String
    var type: String
    var balance: Double
    var notes: String
    var createdAt: Date
    var dueDate: Date?
    var annualPercentageRate: Double?
    var minimumPayment: Double?
    var plannedExtraPayment: Double?
    var mortgageOriginalPrincipal: Double?
    var mortgageTermMonths: Int?
    var mortgageFirstPaymentDate: Date?
    var mortgageMonthlyPropertyTax: Double?
    var mortgageMonthlyInsurance: Double?
    var mortgageMonthlyPMI: Double?
    var mortgageMonthlyEscrow: Double?
    var includeInNetWorth: Bool
    var isArchived: Bool
    var isDefaultChecking: Bool

    init(_ account: Account) {
        id = account.id
        name = account.name
        type = account.typeRaw
        balance = account.balance
        notes = account.notes
        createdAt = account.createdAt
        dueDate = account.dueDate
        annualPercentageRate = account.annualPercentageRate
        minimumPayment = account.minimumPayment
        plannedExtraPayment = account.plannedExtraPayment
        mortgageOriginalPrincipal = account.mortgageOriginalPrincipal
        mortgageTermMonths = account.mortgageTermMonths
        mortgageFirstPaymentDate = account.mortgageFirstPaymentDate
        mortgageMonthlyPropertyTax = account.mortgageMonthlyPropertyTax
        mortgageMonthlyInsurance = account.mortgageMonthlyInsurance
        mortgageMonthlyPMI = account.mortgageMonthlyPMI
        mortgageMonthlyEscrow = account.mortgageMonthlyEscrow
        includeInNetWorth = account.includeInNetWorth
        isArchived = account.isArchived
        isDefaultChecking = account.isDefaultChecking
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(String.self, forKey: .type)
        balance = try container.decode(Double.self, forKey: .balance)
        notes = try container.decode(String.self, forKey: .notes)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        annualPercentageRate = try container.decodeIfPresent(Double.self, forKey: .annualPercentageRate)
        minimumPayment = try container.decodeIfPresent(Double.self, forKey: .minimumPayment)
        plannedExtraPayment = try container.decodeIfPresent(Double.self, forKey: .plannedExtraPayment)
        mortgageOriginalPrincipal = try container.decodeIfPresent(Double.self, forKey: .mortgageOriginalPrincipal)
        mortgageTermMonths = try container.decodeIfPresent(Int.self, forKey: .mortgageTermMonths)
        mortgageFirstPaymentDate = try container.decodeIfPresent(Date.self, forKey: .mortgageFirstPaymentDate)
        mortgageMonthlyPropertyTax = try container.decodeIfPresent(Double.self, forKey: .mortgageMonthlyPropertyTax)
        mortgageMonthlyInsurance = try container.decodeIfPresent(Double.self, forKey: .mortgageMonthlyInsurance)
        mortgageMonthlyPMI = try container.decodeIfPresent(Double.self, forKey: .mortgageMonthlyPMI)
        mortgageMonthlyEscrow = try container.decodeIfPresent(Double.self, forKey: .mortgageMonthlyEscrow)
        includeInNetWorth = try container.decode(Bool.self, forKey: .includeInNetWorth)
        isArchived = try container.decode(Bool.self, forKey: .isArchived)
        isDefaultChecking = try container.decodeIfPresent(Bool.self, forKey: .isDefaultChecking) ?? false
    }
}

struct BudgetDTO: Codable, Equatable {
    var id: UUID
    var name: String
    var limitAmount: Double
    var period: String
    var isActive: Bool
    var colorHex: String
    var createdAt: Date
    var alertsEnabled: Bool
    var lastAlertedThreshold: Int
    var lastAlertedPeriodStart: Date?
    var categoryID: UUID?
    var categoryName: String?

    init(_ budget: Budget) {
        id = budget.id
        name = budget.name
        limitAmount = budget.limitAmount
        period = budget.periodRaw
        isActive = budget.isActive
        colorHex = budget.colorHex
        createdAt = budget.createdAt
        alertsEnabled = budget.alertsEnabled
        lastAlertedThreshold = budget.lastAlertedThresholdRaw
        lastAlertedPeriodStart = budget.lastAlertedPeriodStart
        categoryID = budget.category?.id
        categoryName = budget.category?.name
    }
}

struct RecurringTransactionDTO: Codable, Equatable {
    var id: UUID
    var title: String
    var amount: Double
    var type: String
    var frequency: String
    var startDate: Date
    var nextDueDate: Date
    var endDate: Date?
    var notes: String
    var isActive: Bool
    var createdAt: Date
    var reminderEnabled: Bool
    var reminderDaysBefore: Int
    var categoryID: UUID?
    var categoryName: String?
    var accountID: UUID?
    var accountName: String?

    init(_ recurring: RecurringTransaction) {
        id = recurring.id
        title = recurring.title
        amount = recurring.amount
        type = recurring.typeRaw
        frequency = recurring.frequencyRaw
        startDate = recurring.startDate
        nextDueDate = recurring.nextDueDate
        endDate = recurring.endDate
        notes = recurring.notes
        isActive = recurring.isActive
        createdAt = recurring.createdAt
        reminderEnabled = recurring.reminderEnabled
        reminderDaysBefore = recurring.reminderDaysBefore
        categoryID = recurring.category?.id
        categoryName = recurring.category?.name
        accountID = recurring.account?.id
        accountName = recurring.account?.name
    }
}

struct SavingsGoalDTO: Codable, Equatable {
    var id: UUID
    var name: String
    var targetAmount: Double
    var manualCurrentAmount: Double
    var targetDate: Date?
    var notes: String
    var colorHex: String
    var icon: String
    var createdAt: Date
    var status: String
    var linkedAccountID: UUID?
    var linkedAccountName: String?

    init(_ goal: SavingsGoal) {
        id = goal.id
        name = goal.name
        targetAmount = goal.targetAmount
        manualCurrentAmount = goal.manualCurrentAmount
        targetDate = goal.targetDate
        notes = goal.notes
        colorHex = goal.colorHex
        icon = goal.icon
        createdAt = goal.createdAt
        status = goal.statusRaw
        linkedAccountID = goal.linkedAccount?.id
        linkedAccountName = goal.linkedAccount?.name
    }
}

struct TransferDTO: Codable, Equatable {
    var id: UUID
    var amount: Double
    var date: Date
    var notes: String
    var createdAt: Date
    var fromAccountID: UUID?
    var fromAccountName: String?
    var toAccountID: UUID?
    var toAccountName: String?

    init(_ transfer: Transfer) {
        id = transfer.id
        amount = transfer.amount
        date = transfer.date
        notes = transfer.notes
        createdAt = transfer.createdAt
        fromAccountID = transfer.fromAccount?.id
        fromAccountName = transfer.fromAccount?.name
        toAccountID = transfer.toAccount?.id
        toAccountName = transfer.toAccount?.name
    }
}
