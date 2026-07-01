import Foundation

enum SyncStatus: Equatable {
    case cloudKitActive
    case localOnly(reason: String?)
}
