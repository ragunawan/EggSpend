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
    @State private var showImport = false
    @State private var showResetConfirmation = false
    @State private var resetErrorMessage: String?

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
                        showImport = true
                    } label: {
                        Label("Import CSV", systemImage: "square.and.arrow.down.fill")
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

                    Button(role: .destructive) {
                        showResetConfirmation = true
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
            .sheet(isPresented: $showImport) {
                CSVImportView(importType: .transactions)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Reset All Data?", isPresented: $showResetConfirmation) {
                Button("Reset", role: .destructive) {
                    resetAllData()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This permanently deletes transactions, accounts, budgets, goals, recurring items, category rules, transfers, and custom categories. Default categories will be restored.")
            }
            .alert("Reset Failed", isPresented: resetErrorBinding) {
                Button("OK", role: .cancel) {
                    resetErrorMessage = nil
                }
            } message: {
                Text(resetErrorMessage ?? "The data reset could not be completed.")
            }
        }
    }

    private var resetErrorBinding: Binding<Bool> {
        Binding(
            get: { resetErrorMessage != nil },
            set: { if !$0 { resetErrorMessage = nil } }
        )
    }

    private func resetAllData() {
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
