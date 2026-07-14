import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import LocalAuthentication

/// Data export entry point. Presented as a sheet from `DashboardView`'s
/// toolbar gear button. Scope for this task is export only — no sync
/// status, restore, or currency controls here (those are separate tasks).
struct SettingsView: View {
    /// Shared UserDefaults key for the on-device AI narrative toggle. Read by
    /// both this view's Toggle and `DashboardView`'s narrative enrichment via
    /// `@AppStorage` — defined once here so the key string can't drift.
    static let aiNarrativeStorageKey = "aiNarrativeEnabled"

    /// Shared UserDefaults key for the app-lock toggle. Read here via
    /// `@AppStorage` and by `AppLockController`'s default `lockEnabled`
    /// closure via plain `UserDefaults` — defined once here so the key
    /// string can't drift between the two. `nonisolated` because
    /// `AppLockController`'s default `lockEnabled` closure (a nonisolated
    /// context) reads it directly; `SettingsView` itself infers `@MainActor`
    /// isolation from `View`, which a plain `static let` would otherwise inherit.
    nonisolated static let appLockStorageKey = "appLockEnabled"
    nonisolated static let appearanceStorageKey = "appAppearance"

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppLockController.self) private var appLockController: AppLockController?
    @AppStorage(SettingsView.aiNarrativeStorageKey) private var aiNarrativeEnabled = false
    @AppStorage(SettingsView.appLockStorageKey) private var appLockEnabled = false
    @AppStorage(SettingsView.appearanceStorageKey) private var appearanceRawValue = AppAppearance.system.rawValue
    @State private var showTransactionImport = false
    @State private var showAccountImport = false
    @State private var showBackupImporter = false
    @State private var pendingBackupImportData: Data?
    @State private var pendingResetMode: ResetMode?
    @State private var resetErrorMessage: String?
    @State private var backupImportErrorMessage: String?
    @State private var backupImportSuccessMessage: String?

    @Query private var transactions: [Transaction]
    @Query private var categories: [TransactionCategory]
    @Query private var accounts: [Account]
    @Query private var budgets: [Budget]
    @Query private var recurringTransactions: [RecurringTransaction]
    @Query private var savingsGoals: [SavingsGoal]
    @Query private var transfers: [Transfer]

    // MARK: - Export payloads
    //
    // Built eagerly on the MainActor while `body` evaluates (SwiftUI's
    // @Query arrays are only safe to walk here). `DataExporter` follows
    // @Model relationships (tx.category?.name, tx.account?.name, ...),
    // which can fault-load from the store — that must happen on the main
    // actor, not inside Transferable's exporting closure (see the note
    // below on `CSVExportFile`/`JSONExportFile`).

    private var transactionsFile: CSVExportFile {
        CSVExportFile(
            filename: DataExporter.exportFilename(prefix: "Transactions", ext: "csv"),
            content: DataExporter.transactionsCSV(transactions)
        )
    }

    private var accountsFile: CSVExportFile {
        CSVExportFile(
            filename: DataExporter.exportFilename(prefix: "Accounts", ext: "csv"),
            content: DataExporter.accountsCSV(accounts)
        )
    }

    private var transfersFile: CSVExportFile {
        CSVExportFile(
            filename: DataExporter.exportFilename(prefix: "Transfers", ext: "csv"),
            content: DataExporter.transfersCSV(transfers)
        )
    }

    /// `nil` only if JSON encoding itself fails (not expected in practice);
    /// the row is hidden rather than offering a broken share action.
    private var backupFile: JSONExportFile? {
        guard let data = try? DataExporter.fullBackupJSON(
            transactions: transactions,
            categories: categories,
            accounts: accounts,
            budgets: budgets,
            recurringTransactions: recurringTransactions,
            savingsGoals: savingsGoals,
            transfers: transfers
        ) else { return nil }
        return JSONExportFile(filename: DataExporter.exportFilename(prefix: "Backup", ext: "json"), data: data)
    }

    /// Biometry-adaptive toggle label ("Face ID"/"Touch ID") when the
    /// device can name its own enrolled biometry type; a generic fallback
    /// otherwise. Purely cosmetic — `canEvaluate()` above already gates
    /// whether the section renders at all.
    private var biometricToggleLabel: String {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            return "Require biometrics to unlock"
        }
        switch context.biometryType {
        case .faceID: return "Require Face ID to unlock"
        case .touchID: return "Require Touch ID to unlock"
        default: return "Require biometrics to unlock"
        }
    }

    private var selectedAppearance: Binding<AppAppearance> {
        Binding(
            get: { AppAppearance(rawValue: appearanceRawValue) ?? .system },
            set: { appearanceRawValue = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Appearance", selection: selectedAppearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Display")
                } footer: {
                    Text("Auto matches this device's light or dark appearance.")
                }

                Section("Data") {
                    Button {
                        showTransactionImport = true
                    } label: {
                        Label("Import Transactions (CSV)", systemImage: "square.and.arrow.down.fill")
                    }

                    Button {
                        showAccountImport = true
                    } label: {
                        Label("Import Accounts (CSV)", systemImage: "building.columns.badge.plus")
                    }

                    ShareLink(item: transactionsFile, preview: SharePreview(transactionsFile.filename)) {
                        Label("Export Transactions (CSV)", systemImage: "list.bullet.rectangle.fill")
                    }

                    ShareLink(item: accountsFile, preview: SharePreview(accountsFile.filename)) {
                        Label("Export Accounts (CSV)", systemImage: "building.columns.fill")
                    }

                    ShareLink(item: transfersFile, preview: SharePreview(transfersFile.filename)) {
                        Label("Export Transfers (CSV)", systemImage: "arrow.left.arrow.right.circle.fill")
                    }

                    if let backupFile {
                        ShareLink(item: backupFile, preview: SharePreview(backupFile.filename)) {
                            Label("Full Backup (JSON)", systemImage: "externaldrive.fill")
                        }
                    }

                    Button {
                        showBackupImporter = true
                    } label: {
                        Label("Import Full Backup (JSON)", systemImage: "externaldrive.badge.plus")
                    }

                    Button(role: .destructive) {
                        pendingResetMode = .sampleData
                    } label: {
                        Label("Reset All Data and use Sample Data", systemImage: "wand.and.stars")
                    }

                    Button(role: .destructive) {
                        pendingResetMode = .empty
                    } label: {
                        Label("Reset All Data", systemImage: "trash.fill")
                    }
                }

                Section("Manage") {
                    NavigationLink {
                        CategoryManagementView()
                    } label: {
                        Label("Categories", systemImage: "tag.fill")
                    }

                    NavigationLink {
                        RecurringTransactionsView()
                    } label: {
                        Label("Recurring", systemImage: "repeat.circle.fill")
                    }

                    NavigationLink {
                        SubscriptionAuditView()
                    } label: {
                        Label("Subscription audit", systemImage: "magnifyingglass.circle.fill")
                    }
                }

                // Only rendered when this device can actually evaluate
                // device-owner authentication at all (e.g. hidden on a
                // Simulator with no Face ID/Touch ID enrolled) — mirrors the
                // Intelligence section's availability-gating precedent below.
                if LiveBiometricAuthenticator().canEvaluate() {
                    Section {
                        Toggle(biometricToggleLabel, isOn: $appLockEnabled)
                            .onChange(of: appLockEnabled) { _, newValue in
                                if !newValue {
                                    appLockController?.refreshForLockSettingChange()
                                }
                            }
                    } header: {
                        Text("Privacy")
                    } footer: {
                        Text("Locks EggSpend's screens behind your device's biometrics or passcode when you reopen the app. This protects who can view your data on this device — it does not encrypt the underlying data.")
                    }
                }

                // Only rendered when the on-device model is actually usable on
                // this device (Apple Intelligence enabled and ready) — on any
                // other device the toggle is absent entirely, per the T19 spec.
                if NarrativeGenerator.isAvailable() {
                    Section {
                        Toggle("Enrich summaries with on-device AI", isOn: $aiNarrativeEnabled)
                    } header: {
                        Text("Intelligence")
                    } footer: {
                        Text("Rewrites the \"What changed this month?\" summary in a more natural tone. Processing happens entirely on this device — nothing is ever sent anywhere — and every number always comes from your actual data.")
                    }
                }
            }
            .sheet(isPresented: $showTransactionImport) {
                CSVImportView(importType: .transactions)
            }
            .sheet(isPresented: $showAccountImport) {
                CSVImportView(importType: .accounts)
            }
            .fileImporter(
                isPresented: $showBackupImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleBackupImportSelection(result)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(
                pendingResetMode?.confirmationTitle ?? "Reset All Data?",
                isPresented: resetConfirmationBinding
            ) {
                Button(pendingResetMode?.confirmationButtonTitle ?? "Reset", role: .destructive) {
                    if let pendingResetMode {
                        resetAllData(useSampleData: pendingResetMode == .sampleData)
                    }
                    pendingResetMode = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingResetMode = nil
                }
            } message: {
                Text(pendingResetMode?.confirmationMessage ?? "This permanently deletes transactions, accounts, budgets, goals, recurring items, category rules, transfers, and custom categories. Default categories will be restored.")
            }
            .alert("Reset Failed", isPresented: resetErrorBinding) {
                Button("OK", role: .cancel) {
                    resetErrorMessage = nil
                }
            } message: {
                Text(resetErrorMessage ?? "The data reset could not be completed.")
            }
            .alert("Import Full Backup?", isPresented: backupImportConfirmationBinding) {
                Button("Import Backup", role: .destructive) {
                    importPendingBackup()
                }
                Button("Cancel", role: .cancel) {
                    pendingBackupImportData = nil
                }
            } message: {
                Text("This replaces all current EggSpend data on this device with the selected JSON backup.")
            }
            .alert("Import Failed", isPresented: backupImportErrorBinding) {
                Button("OK", role: .cancel) {
                    backupImportErrorMessage = nil
                }
            } message: {
                Text(backupImportErrorMessage ?? "The backup could not be imported.")
            }
            .alert("Import Complete", isPresented: backupImportSuccessBinding) {
                Button("OK", role: .cancel) {
                    backupImportSuccessMessage = nil
                }
            } message: {
                Text(backupImportSuccessMessage ?? "Your backup was imported.")
            }
        }
    }

    private var resetErrorBinding: Binding<Bool> {
        Binding(
            get: { resetErrorMessage != nil },
            set: { if !$0 { resetErrorMessage = nil } }
        )
    }

    private var resetConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingResetMode != nil },
            set: { if !$0 { pendingResetMode = nil } }
        )
    }

    private var backupImportConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingBackupImportData != nil },
            set: { if !$0 { pendingBackupImportData = nil } }
        )
    }

    private var backupImportErrorBinding: Binding<Bool> {
        Binding(
            get: { backupImportErrorMessage != nil },
            set: { if !$0 { backupImportErrorMessage = nil } }
        )
    }

    private var backupImportSuccessBinding: Binding<Bool> {
        Binding(
            get: { backupImportSuccessMessage != nil },
            set: { if !$0 { backupImportSuccessMessage = nil } }
        )
    }

    private func handleBackupImportSelection(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            pendingBackupImportData = try Data(contentsOf: url)
        } catch {
            backupImportErrorMessage = error.localizedDescription
        }
    }

    private func importPendingBackup() {
        guard let data = pendingBackupImportData else { return }
        pendingBackupImportData = nil
        do {
            try DataExporter.restoreFullBackup(from: data, in: modelContext)
            backupImportSuccessMessage = "Your JSON backup was imported."
        } catch {
            modelContext.rollback()
            backupImportErrorMessage = error.localizedDescription
        }
    }

    private func resetAllData(useSampleData: Bool = false) {
        do {
            try deleteAll(CategoryRule.self)
            try deleteAll(BalanceSnapshot.self)
            try deleteAll(Transfer.self)
            try deleteAll(RecurringTransaction.self)
            try deleteAll(SavingsGoal.self)
            try deleteAll(Budget.self)
            try deleteAll(Transaction.self)
            try deleteAll(Account.self)
            try deleteAll(TransactionCategory.self)
            insertDefaultCategories()
            try modelContext.save()
            if useSampleData {
                PersistenceController.seedPreviewTransactionsIfNeeded(modelContainer: modelContext.container)
            }
        } catch {
            modelContext.rollback()
            resetErrorMessage = error.localizedDescription
        }
    }

    private func deleteAll<T: PersistentModel>(_ modelType: T.Type) throws {
        for item in try modelContext.fetch(FetchDescriptor<T>()) {
            modelContext.delete(item)
        }
    }

    private func insertDefaultCategories() {
        let defaults: [(String, String, String, TransactionType?)] = [
            ("Food & Dining", "fork.knife", "E67E22", .expense),
            ("Shopping", "bag.fill", "9B59B6", .expense),
            ("Transport", "car.fill", "3498DB", .expense),
            ("Housing", "house.fill", "1ABC9C", .expense),
            ("Healthcare", "cross.fill", "E74C3C", .expense),
            ("Entertainment", "tv.fill", "F39C12", .expense),
            ("Education", "book.fill", "2980B9", .expense),
            ("Utilities", "bolt.fill", "7F8C8D", .expense),
            ("Travel", "airplane", "16A085", .expense),
            ("Salary", "briefcase.fill", "27AE60", .income),
            ("Freelance", "laptopcomputer", "2ECC71", .income),
            ("Investment Return", "chart.line.uptrend.xyaxis", "F1C40F", .income),
            ("Other", "ellipsis.circle.fill", "95A5A6", nil)
        ]

        for (index, category) in defaults.enumerated() {
            let (name, icon, colorHex, typeFilter) = category
            modelContext.insert(TransactionCategory(
                name: name,
                icon: icon,
                colorHex: colorHex,
                typeFilter: typeFilter,
                sortOrder: index
            ))
        }
    }
}

private enum ResetMode {
    case empty
    case sampleData

    var confirmationTitle: String {
        switch self {
        case .empty:
            return "Reset All Data?"
        case .sampleData:
            return "Reset and Use Sample Data?"
        }
    }

    var confirmationButtonTitle: String {
        switch self {
        case .empty:
            return "Reset"
        case .sampleData:
            return "Reset and Add Samples"
        }
    }

    var confirmationMessage: String {
        switch self {
        case .empty:
            return "This permanently deletes transactions, accounts, budgets, goals, recurring items, category rules, transfers, and custom categories. Default categories will be restored."
        case .sampleData:
            return "This permanently deletes transactions, accounts, budgets, goals, recurring items, category rules, transfers, and custom categories, then loads sample transactions, accounts, budgets, goals, recurring items, and default categories."
        }
    }
}

// MARK: - Transferable wrappers
//
// These hold plain, already-`Sendable` `String`/`Data` payloads rendered
// on the MainActor in `SettingsView` above — never a closure capturing
// @Model arrays. `DataRepresentation`'s exporting closure is
// `@escaping @Sendable (Item) async throws -> Data` and CoreTransferable
// may invoke it off the main actor (e.g. for large exports, so sharing
// doesn't block the UI). Touching SwiftData @Model instances from a
// non-owning thread is unsupported and can crash or corrupt reads, so the
// exporting closure here only wraps an already-computed value — it never
// walks a model relationship.

private struct CSVExportFile: Transferable {
    let filename: String
    let content: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { file in
            Data(file.content.utf8)
        }
        .suggestedFileName { file in file.filename }
    }
}

private struct JSONExportFile: Transferable {
    let filename: String
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { file in
            file.data
        }
        .suggestedFileName { file in file.filename }
    }
}

#Preview {
    SettingsView()
        .modelContainer(PersistenceController.previewContainer())
}
