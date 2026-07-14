import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: – Import type

enum CSVImportType {
    case transactions
    case accounts

    var title: String {
        switch self {
        case .transactions: return "Import Transactions"
        case .accounts:     return "Import Accounts"
        }
    }
    var icon: String {
        switch self {
        case .transactions: return "list.bullet.rectangle.fill"
        case .accounts:     return "building.columns.fill"
        }
    }
}

// MARK: – Main view

struct CSVImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var categories: [TransactionCategory]
    @Query(sort: \Account.name) private var accounts: [Account]
    @Query private var categoryRules: [CategoryRule]

    let importType: CSVImportType

    // File picking
    @State private var showFilePicker = false
    @State private var fileName = ""

    // Parsed state
    @State private var headers:  [String] = []
    @State private var rawRows:  [[String]] = []
    @State private var mapping:  ColumnMapping = ColumnMapping()

    // Results
    @State private var txResults:   [ParsedTransactionResult] = []
    @State private var acctResults: [ParsedAccountResult]     = []

    // Account linking (transactions import only)
    @State private var selectedImportAccount: Account? = nil
    @State private var applyBalanceToggle = true

    // UI state
    @State private var step: Step = .pick
    @State private var errorMessage: String? = nil
    @State private var importComplete = false
    @State private var importedCount  = 0
    @State private var skippedCount   = 0
    @State private var duplicateSkippedCount = 0

    enum Step { case pick, map, preview, done }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .pick:    pickStep
                case .map:     mapStep
                case .preview: previewStep
                case .done:    doneStep
                }
            }
            .navigationTitle(importType.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(step == .done)
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.commaSeparatedText, .plainText, .text],
            allowsMultipleSelection: false
        ) { result in
            handleFilePicked(result)
        }
    }

    // MARK: - Step 1: Pick file

    private var pickStep: some View {
        VStack(spacing: 32) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(Color.yolk.opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: "doc.badge.plus")
                    .font(.largeTitle)
                    .foregroundStyle(Color.yolk)
            }

            VStack(spacing: 8) {
                Text("Choose a CSV File")
                    .font(.title2).fontWeight(.semibold).foregroundStyle(Color.nestBrown)
                Text(importType == .transactions
                     ? "Supports exports from Chase, Bank of America, Mint, Apple Card, and any standard CSV."
                     : "CSV should have columns for account name, type, and balance.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Format hint
            VStack(alignment: .leading, spacing: 6) {
                Text("Expected columns")
                    .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                    .textCase(.uppercase)
                if importType == .transactions {
                    HintRow(cols: ["Date", "Description", "Amount"])
                    HintRow(cols: ["Category (opt.)", "Notes (opt.)", "Type (opt.)"])
                } else {
                    HintRow(cols: ["Name", "Type", "Balance"])
                    HintRow(cols: ["Notes (opt.)"])
                }
            }
            .padding()
            .background(Color.nestCream, in: RoundedRectangle(cornerRadius: Radius.card))
            .padding(.horizontal, 32)

            Button {
                showFilePicker = true
            } label: {
                Label("Choose File", systemImage: "folder.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.yolk, in: RoundedRectangle(cornerRadius: Radius.card))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    // MARK: - Step 2: Map columns

    private var mapStep: some View {
        List {
            Section {
                Label(fileName, systemImage: "doc.text.fill")
                    .foregroundStyle(Color.nestBrown)
                Text("\(rawRows.count) data rows · \(headers.count) columns detected")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if importType == .transactions {
                Section {
                    columnPicker("Date *",        selection: $mapping.dateColumn)
                    columnPicker("Payee / Desc *", selection: $mapping.titleColumn)
                    columnPicker("Amount *",       selection: $mapping.amountColumn)
                } header: { Text("Required") }

                Section {
                    columnPicker("Transaction Type", selection: $mapping.typeColumn)
                    columnPicker("Category",         selection: $mapping.categoryColumn)
                    columnPicker("Notes",            selection: $mapping.notesColumn)
                } header: { Text("Optional") }

                Section {
                    Toggle("Negative amount = Expense", isOn: $mapping.negativeIsExpense)
                } header: { Text("Amount Interpretation") }
                  footer: { Text("When no Type column is mapped, sign of amount determines income vs. expense.") }

                Section {
                    Picker("Import into account", selection: $selectedImportAccount) {
                        Text("None").tag(Optional<Account>.none)
                        ForEach(availableAccounts) { account in
                            Label(account.name, systemImage: account.type.icon)
                                .tag(Optional(account))
                        }
                    }
                    if selectedImportAccount != nil {
                        Toggle("Adjust account balance by imported transactions", isOn: $applyBalanceToggle)
                    }
                } header: { Text("Account") }
                  footer: { Text("Linking an account lets each imported transaction update its balance.") }
                  .onChange(of: selectedImportAccount) { oldValue, newValue in
                      if oldValue == nil && newValue != nil {
                          applyBalanceToggle = true
                      }
                  }

            } else {
                Section {
                    columnPicker("Account Name *", selection: $mapping.nameColumn)
                    columnPicker("Balance *",      selection: $mapping.balanceColumn)
                } header: { Text("Required") }

                Section {
                    columnPicker("Account Type", selection: $mapping.acctTypeColumn)
                    columnPicker("Notes",        selection: $mapping.acctNotesColumn)
                } header: { Text("Optional") }
            }

            Section {
                Button("Preview →") { buildPreview() }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundStyle(Color.yolk)
                    .fontWeight(.semibold)
                    .disabled(!canProceedFromMap)
            }
        }
        .listStyle(.insetGrouped)
    }

    private var canProceedFromMap: Bool {
        if importType == .transactions {
            return mapping.dateColumn != nil && mapping.titleColumn != nil && mapping.amountColumn != nil
        } else {
            return mapping.nameColumn != nil && mapping.balanceColumn != nil
        }
    }

    private var availableAccounts: [Account] {
        accounts.filter { !$0.isArchived }
    }

    @ViewBuilder
    private func columnPicker(_ label: String, selection: Binding<String?>) -> some View {
        Picker(label, selection: selection) {
            Text("— None —").tag(Optional<String>.none)
            ForEach(headers, id: \.self) { h in
                Text(h).tag(Optional(h))
            }
        }
    }

    // MARK: - Step 3: Preview

    private var previewStep: some View {
        VStack(spacing: 0) {
            // Summary bar
            summaryBar

            List {
                Section {
                    if importType == .transactions {
                        ForEach(txResults.prefix(50)) { result in
                            TransactionPreviewRow(result: result)
                        }
                        if txResults.count > 50 {
                            Text("… and \(txResults.count - 50) more rows")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(acctResults.prefix(50)) { result in
                            AccountPreviewRow(result: result)
                        }
                        if acctResults.count > 50 {
                            Text("… and \(acctResults.count - 50) more rows")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Preview (first 50 rows)")
                }
            }
            .listStyle(.insetGrouped)

            if importType == .transactions, let account = selectedImportAccount, applyBalanceToggle {
                let effect = netBalanceEffect(of: txResults)
                Text("Will \(effect < 0 ? "decrease" : "increase") \(account.name) by \(abs(effect), format: .currency(code: CurrencyFormat.code))")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 6)
            }

            // Import button
            Button(action: performImport) {
                let validCount = importType == .transactions
                    ? txResults.filter(\.willImport).count
                    : acctResults.filter(\.isValid).count
                Label("Import \(validCount) \(importType == .transactions ? "Transactions" : "Accounts")",
                      systemImage: "square.and.arrow.down.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.nestBrown, in: RoundedRectangle(cornerRadius: Radius.card))
                    .foregroundStyle(.white)
            }
            .padding()
        }
    }

    private var summaryBar: some View {
        let ready: Int
        let invalid: Int
        let duplicates: Int
        if importType == .transactions {
            ready = txResults.filter(\.willImport).count
            invalid = txResults.filter { !$0.isValid }.count
            duplicates = txResults.filter { $0.isValid && $0.isDuplicate }.count
        } else {
            ready = acctResults.filter(\.isValid).count
            invalid = acctResults.filter { !$0.isValid }.count
            duplicates = 0
        }

        return HStack {
            Label("\(ready) ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Color.nestLeafGreen)
            Spacer()
            if duplicates > 0 {
                Label("\(duplicates) duplicates", systemImage: "doc.on.doc.fill")
                    .foregroundStyle(Color.warningTone)
            }
            if invalid > 0 {
                Label("\(invalid) skipped", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.warningTone)
            }
        }
        .font(.subheadline).fontWeight(.medium)
        .padding(.horizontal).padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    // MARK: - Step 4: Done

    private var doneStep: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle().fill(Color.nestLeafGreen.opacity(0.15)).frame(width: 100, height: 100)
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle).foregroundStyle(Color.nestLeafGreen)
            }
            VStack(spacing: 8) {
                Text("Import Complete")
                    .font(.title2).fontWeight(.bold).foregroundStyle(Color.nestBrown)
                Text("\(importedCount) \(importType == .transactions ? "transactions" : "accounts") added")
                    .foregroundStyle(.secondary)
                if skippedCount > 0 {
                    Text("\(skippedCount) rows skipped (invalid data)")
                        .font(.caption).foregroundStyle(Color.warningTone)
                }
                if duplicateSkippedCount > 0 {
                    Text("\(duplicateSkippedCount) duplicates skipped")
                        .font(.caption).foregroundStyle(Color.warningTone)
                }
            }
            Button("Done") { dismiss() }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.nestBrown, in: RoundedRectangle(cornerRadius: Radius.card))
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Logic

    private func handleFilePicked(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let err):
            errorMessage = err.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            fileName = url.lastPathComponent
            let gotAccess = url.startAccessingSecurityScopedResource()
            defer { if gotAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
                    ?? ""
                let (h, r) = CSVParser.parse(text)
                guard !h.isEmpty else {
                    errorMessage = "Could not read CSV headers. Make sure the file has a header row."
                    return
                }
                headers = h
                rawRows = r
                mapping = importType == .transactions
                    ? .autoDetectTransaction(headers: h)
                    : .autoDetectAccount(headers: h)
                step = .map
            } catch {
                errorMessage = "Could not read file: \(error.localizedDescription)"
            }
        }
    }

    private func buildPreview() {
        if importType == .transactions {
            let parsed = CSVParser.parseTransactionRows(rows: rawRows, headers: headers, mapping: mapping)
            // Unfiltered fetch + in-Swift filter (repo precedent: RecurringTransaction.swift,
            // BudgetAlertCoordinator.swift) rather than a #Predicate date range.
            // Includes isGenerated (recurring-materialized) transactions deliberately: a bank
            // row that collides with an already-materialized recurring charge is a real duplicate.
            let existingTransactions = (try? modelContext.fetch(FetchDescriptor<Transaction>())) ?? []
            let existingKeys = Set(existingTransactions.map {
                duplicateKey(date: $0.date, amount: $0.amount, title: $0.title, accountID: $0.account?.id)
            })
            let marked = markDuplicates(in: parsed, existingKeys: existingKeys, accountID: selectedImportAccount?.id)
            txResults = applyCategoryRules(in: marked, rules: categoryRules, categories: categories)
        } else {
            acctResults = CSVParser.parseAccountRows(rows: rawRows, headers: headers, mapping: mapping)
        }
        step = .preview
    }

    private func performImport() {
        importedCount = 0
        skippedCount  = 0
        duplicateSkippedCount = 0

        var insertedTransactions: [Transaction] = []
        var insertedAccounts: [Account] = []

        if importType == .transactions {
            // Build category lookup (case-insensitive)
            let catMap = Dictionary(
                categories.map { ($0.name.lowercased(), $0) },
                uniquingKeysWith: { first, _ in first }
            )
            for result in txResults {
                guard result.isValid, let date = result.date, let amount = result.amount else {
                    skippedCount += 1
                    continue
                }
                // Trust the isDuplicate flag baked in by buildPreview()'s markDuplicates()
                // call — do not re-derive here, so there's a single source of truth.
                if result.isDuplicate {
                    duplicateSkippedCount += 1
                    continue
                }
                let category = result.categoryName.flatMap { catMap[$0.lowercased()] }
                let tx = Transaction(
                    title:    result.title,
                    amount:   amount,
                    date:     date,
                    type:     result.type,
                    category: category,
                    account:  selectedImportAccount,
                    notes:    result.notes
                )
                modelContext.insert(tx)
                insertedTransactions.append(tx)
                if applyBalanceToggle {
                    AccountBalanceService.apply(tx, to: selectedImportAccount)
                }
                importedCount += 1
            }
        } else {
            for result in acctResults {
                guard result.isValid, let balance = result.balance else {
                    skippedCount += 1
                    continue
                }
                let account = Account(name: result.name, type: result.type,
                                      balance: balance, notes: result.notes)
                modelContext.insert(account)
                insertedAccounts.append(account)
                importedCount += 1
            }
        }

        do {
            try modelContext.save()
        } catch {
            // Targeted deletes rather than rollback: this call's own inserted
            // rows are removed so a retry starts clean, while any unrelated
            // unsaved edits elsewhere in the shared context survive (rollback
            // would have discarded those too). selectedImportAccount is a
            // pre-existing object outside that set, so its balance mutations
            // must be undone explicitly before the transactions are deleted.
            if applyBalanceToggle {
                for tx in insertedTransactions {
                    AccountBalanceService.reverse(tx, from: selectedImportAccount)
                }
            }
            for tx in insertedTransactions { modelContext.delete(tx) }
            for account in insertedAccounts { modelContext.delete(account) }
            importedCount = 0
            errorMessage = "Import failed to save: \(error.localizedDescription)"
            return
        }
        if importType == .transactions {
            BudgetAlertCoordinator.checkBudgets(context: modelContext)
        }
        step = .done
    }
}

/// Net signed effect that importing the given rows would have on an account's
/// balance — income adds, expense subtracts. Mirrors `performImport()`'s own
/// `willImport` filter so the preview sentence matches what actually gets applied.
func netBalanceEffect(of results: [ParsedTransactionResult]) -> Double {
    results.filter(\.willImport).reduce(0) { $0 + $1.type.sign * ($1.amount ?? 0) }
}

// MARK: – Duplicate detection

/// Same calendar day + same amount + case/whitespace-normalized title + same
/// account when set. Intentionally has no type/sign dimension: a same-day,
/// same-amount, same-title refund and purchase in the same account collide as
/// duplicates — accepted v1 imprecision per the resolved product decision.
struct TransactionDuplicateKey: Hashable {
    let day: Date
    let amount: Double
    let normalizedTitle: String
    let accountID: UUID?
}

func duplicateKey(date: Date, amount: Double, title: String, accountID: UUID?) -> TransactionDuplicateKey {
    TransactionDuplicateKey(
        day: Calendar.current.startOfDay(for: date),
        amount: amount,
        normalizedTitle: CSVParser.normalizedTitle(title),
        accountID: accountID
    )
}

/// Marks structurally valid rows whose duplicate key already exists (either in
/// `existingKeys` — persisted transactions — or earlier in this same file) as
/// `isDuplicate`. The first occurrence of a key imports; later identical rows
/// within the file are marked so within-file duplicates are also caught.
/// Structurally invalid rows (no date/amount) pass through unmarked.
func markDuplicates(
    in results: [ParsedTransactionResult],
    existingKeys: Set<TransactionDuplicateKey>,
    accountID: UUID?
) -> [ParsedTransactionResult] {
    var seen = existingKeys
    return results.map { result in
        var result = result
        guard result.isValid, let date = result.date, let amount = result.amount else { return result }
        let key = duplicateKey(date: date, amount: amount, title: result.title, accountID: accountID)
        if seen.contains(key) {
            result.isDuplicate = true
        } else {
            seen.insert(key)
        }
        return result
    }
}

/// Auto-assigns a category to rows that don't already have one, using rules
/// learned from the user's own prior manual categorization
/// (`CategoryRuleEngine`). Rows with a CSV-specified category are always left
/// untouched — never overwrite an explicit signal with a guess.
func applyCategoryRules(
    in results: [ParsedTransactionResult],
    rules: [CategoryRule],
    categories: [TransactionCategory]
) -> [ParsedTransactionResult] {
    results.map { result in
        var result = result
        guard result.categoryName == nil else { return result }
        if let match = CategoryRuleEngine.categoryFor(title: result.title, rules: rules, categories: categories) {
            result.categoryName = match.name
            result.isAutoAssignedCategory = true
        }
        return result
    }
}

// MARK: – Preview rows

private struct TransactionPreviewRow: View {
    let result: ParsedTransactionResult

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: !result.isValid
                  ? "exclamationmark.triangle.fill"
                  : (result.isDuplicate
                     ? "doc.on.doc.fill"
                     : (result.type == .income ? "arrow.down.circle.fill" : "arrow.up.circle.fill")))
                .foregroundStyle(!result.isValid
                                 ? Color.warningTone
                                 : (result.isDuplicate
                                    ? Color.warningTone
                                    : (result.type == .income ? Color.nestLeafGreen : Color.negative)))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.title).font(.body).lineLimit(1)
                if result.isValid && result.isDuplicate {
                    Text("Duplicate — will skip").font(.caption).foregroundStyle(Color.warningTone)
                } else if let err = result.validationError {
                    Text(err).font(.caption).foregroundStyle(Color.warningTone)
                } else {
                    HStack(spacing: 6) {
                        if let date = result.date {
                            Text(date, style: .date).font(.caption).foregroundStyle(.secondary)
                        }
                        if let cat = result.categoryName {
                            Text(cat).font(.caption).foregroundStyle(.secondary)
                        }
                        if result.isAutoAssignedCategory {
                            Label("Auto", systemImage: "wand.and.stars")
                                .font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.yolk.opacity(0.15), in: Capsule())
                                .foregroundStyle(Color.yolk)
                                .accessibilityLabel("Category auto-assigned")
                        }
                    }
                }
            }

            Spacer()

            if let amount = result.amount {
                AmountLabel(amount: amount, type: result.type, font: .callout)
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
        .opacity(result.willImport ? 1 : 0.5)
    }
}

private struct AccountPreviewRow: View {
    let result: ParsedAccountResult

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: result.isValid ? result.type.icon : "exclamationmark.triangle.fill")
                .foregroundStyle(result.isValid
                                 ? (result.type.isAsset ? Color.nestLeafGreen : Color.negative)
                                 : Color.warningTone)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.name).font(.body).lineLimit(1)
                if let err = result.validationError {
                    Text(err).font(.caption).foregroundStyle(Color.warningTone)
                } else {
                    Text(result.type.rawValue).font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let balance = result.balance {
                Text(abs(balance), format: .currency(code: CurrencyFormat.code))
                    .font(.system(.callout, design: .rounded, weight: .medium))
                    .foregroundStyle(result.type.isAsset ? Color.nestLeafGreen : Color.negative)
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
        .opacity(result.isValid ? 1 : 0.5)
    }
}

// MARK: – Column hint chip row

private struct HintRow: View {
    let cols: [String]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(cols, id: \.self) { col in
                Text(col)
                    .font(.caption2)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.twig.opacity(0.15), in: Capsule())
                    .foregroundStyle(Color.twig)
            }
        }
    }
}

#Preview {
    CSVImportView(importType: .transactions)
        .modelContainer(PersistenceController.previewContainer())
}
