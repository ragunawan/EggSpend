import Foundation

enum SyncStatus: Equatable {
    case cloudKitActive
    case localOnly(reason: String?)

    /// The status resolved at launch by `EggSpendApp`'s container initializer.
    /// Written exactly once, before any UI reads it; `nil` only in previews and
    /// tests, which never run the app's container initializer (readers should
    /// hide sync UI in that case rather than guess). `nonisolated(unsafe)` is
    /// safe under the write-once-at-launch discipline — same pattern as
    /// `CurrencyFormat.override`.
    nonisolated(unsafe) static var current: SyncStatus?
}
