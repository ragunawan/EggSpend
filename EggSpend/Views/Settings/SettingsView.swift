import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Data export entry point. Presented as a sheet from `DashboardView`'s
/// toolbar gear button. Scope for this task is export only — no sync
/// status, currency, or restore controls here (those are separate tasks).
struct SettingsView: View {
    /// Shared UserDefaults key for the on-device AI narrative toggle. Read by
    /// both this view's Toggle and `DashboardView`'s narrative enrichment via
    /// `@AppStorage` — defined once here so the key string can't drift.
    static let aiNarrativeStorageKey = "aiNarrativeEnabled"

    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsView.aiNarrativeStorageKey) private var aiNarrativeEnabled = false

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

    var body: some View {
        NavigationStack {
            Form {
                Section("Data") {
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
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
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
