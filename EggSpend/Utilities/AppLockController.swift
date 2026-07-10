import Foundation
import LocalAuthentication
import SwiftUI

/// Seam over `LAContext` so the lock state machine is fully unit-testable
/// without any live biometric hardware — mirrors `NarrativeModelSession`'s
/// protocol-seam precedent for a similarly untestable-live-API surface.
protocol BiometricAuthenticating: Sendable {
    /// True iff this device can currently evaluate device-owner
    /// authentication (biometrics or passcode) at all — used to decide
    /// whether the Settings toggle is even shown.
    func canEvaluate() -> Bool

    /// Attempts a single authentication challenge. Returns `true` on
    /// success, `false` on a user-facing failure/cancellation, or throws on
    /// an unexpected system error — either non-success outcome leaves the
    /// caller locked with no automatic retry.
    func evaluate(reason: String) async throws -> Bool
}

/// Live `LAContext`-backed authenticator. A **fresh `LAContext` is created
/// for every call** — Apple's recommended clean-state-per-attempt pattern,
/// which avoids any stale invalidation/biometry state carrying over from a
/// previous attempt.
struct LiveBiometricAuthenticator: BiometricAuthenticating {
    func canEvaluate() -> Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// `.deviceOwnerAuthentication` (not `.deviceOwnerAuthenticationWithBiometrics`)
    /// is deliberate: it natively falls back to the device passcode UI after
    /// a failed or unavailable biometric attempt, satisfying the "failed
    /// biometrics offer device passcode" acceptance bar with a single
    /// policy — no second, manually-chained passcode-only evaluation call
    /// is needed, and there is no path where a failed biometric attempt
    /// leaves the user with no recovery option.
    func evaluate(reason: String) async throws -> Bool {
        try await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    }
}

/// Privacy screen gating the app's own UI behind device biometrics/passcode
/// on cold launch and every background→foreground transition.
///
/// **This is a UI privacy gate, not encryption.** The underlying
/// SwiftData/CloudKit store is completely unchanged and unencrypted by this
/// controller — it only decides whether `LockScreenView` covers the rest of
/// the app's UI while `isLocked` is true.
///
/// State machine: `.background` arms the lock (`isLocked = true`) iff the
/// Settings toggle is on; `.active` triggers a fresh authentication attempt
/// iff the lock is currently armed and no attempt is already in flight.
/// `.inactive` is deliberately never wired to any method here — the Face ID
/// system prompt itself transitions the scene through `.inactive` before
/// returning to `.active`, so treating `.inactive` as an arm/disarm trigger
/// would re-arm the lock around the very prompt meant to clear it,
/// producing a re-lock loop.
///
/// **Never-brick guarantee:** `.deviceOwnerAuthentication` always offers the
/// device passcode after a failed/unavailable biometric attempt, a failed
/// attempt simply leaves `isLocked` unchanged (never a permanent lockout),
/// and `LockScreenView`'s Unlock button always offers a fresh, user-initiated
/// retry. No transient auth state is persisted across launches — every cold
/// launch re-arms cleanly from `lockEnabled()` alone, so a force-quit can
/// never leave the app stuck in a corrupted lock state. Additionally, if the
/// device loses *all* device-owner auth capability after the toggle was
/// enabled (e.g. the user later removes their passcode, which also disables
/// biometrics), `authenticate()` detects that via `canEvaluate()` and
/// auto-unlocks rather than trapping the user behind a Settings screen that
/// is itself unreachable while locked — app-level security can never exceed
/// OS-level security.
/// `@MainActor`-isolated because every call site is SwiftUI (scenePhase
/// handling, the lock cover's button/on-appear) — pinning isolation here
/// keeps `Task { await controller.authenticate() }` at call sites free of
/// cross-actor "sending" concerns for this non-`Sendable` reference type.
@MainActor
@Observable
final class AppLockController {
    private(set) var isLocked: Bool
    private(set) var authInFlight = false

    private let authenticator: BiometricAuthenticating
    private let lockEnabled: () -> Bool

    /// `lockEnabled` defaults to reading the `@AppStorage`-backed toggle
    /// directly from `UserDefaults` (rather than SwiftUI's `@AppStorage`
    /// itself) so this controller stays SwiftUI-free and independently
    /// testable; tests inject a deterministic closure instead.
    init(
        authenticator: BiometricAuthenticating = LiveBiometricAuthenticator(),
        lockEnabled: @escaping () -> Bool = {
            UserDefaults.standard.bool(forKey: SettingsView.appLockStorageKey)
        }
    ) {
        self.authenticator = authenticator
        self.lockEnabled = lockEnabled
        // Cold launch is pre-armed whenever the setting is on — never rely
        // on a later `.active` transition to arm retroactively, since a
        // fresh process launch never fires `.background` first.
        self.isLocked = lockEnabled()
    }

    /// Call from `scenePhase == .background`. Arms the lock; a no-op when
    /// the setting is off.
    func sceneDidEnterBackground() {
        if lockEnabled() {
            isLocked = true
        }
    }

    /// Call from `scenePhase == .active`. Triggers a fresh authentication
    /// attempt iff the lock is currently armed and nothing is already in
    /// flight.
    func sceneDidBecomeActive() async {
        guard lockEnabled(), isLocked, !authInFlight else { return }
        await authenticate()
    }

    /// Runs a single authentication attempt. Guarded by `authInFlight` so a
    /// concurrent trigger (e.g. the lock cover's own on-appear trigger
    /// racing a `.active` transition) never double-prompts. Success
    /// unlocks; failure or a thrown error leaves the lock armed with no
    /// automatic retry — the user retries via `LockScreenView`'s Unlock
    /// button, or by returning to `.active` again.
    func authenticate() async {
        guard !authInFlight else { return }
        authInFlight = true
        defer { authInFlight = false }
        do {
            if try await authenticator.evaluate(reason: "Unlock EggSpend") {
                isLocked = false
            }
        } catch {
            // Failed/cancelled biometrics or passcode — stay locked, no
            // auto-retry, no logging (this path carries no data worth
            // recording and the user already sees the lock screen).
            //
            // Recovery exception: if the device no longer has *any*
            // device-owner auth configured at all (e.g. the user removed
            // their passcode after enabling this toggle, which also
            // disables biometrics), every future `evaluate()` call would
            // throw forever — and Settings, the only way to turn this
            // toggle off, is itself behind this same lock, which would
            // otherwise be a permanent lockout. App-level security can
            // never exceed OS-level security: if `canEvaluate()` reports
            // no auth mechanism exists, unlock rather than trap the user
            // out of their own data. This reuses the exact same
            // "is this feature even available" check the Settings
            // toggle's own visibility gate already relies on, rather than
            // matching specific `LAError` codes.
            if !authenticator.canEvaluate() {
                isLocked = false
            }
        }
    }

    /// Call when the Settings toggle flips off. If currently locked, this
    /// unlocks immediately — "OFF restores current behavior" per spec.
    func refreshForLockSettingChange() {
        if !lockEnabled() {
            isLocked = false
        }
    }
}

/// Full-screen privacy gate shown while `AppLockController.isLocked` is
/// true. Mounted via `.fullScreenCover` at the `WindowGroup` root so it
/// covers any actively-presented sheet (e.g. `SettingsView`) as well as the
/// tab content itself.
struct LockScreenView: View {
    let controller: AppLockController

    var body: some View {
        ZStack {
            Color.nestCream.ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.nestBrown)
                    .accessibilityHidden(true)

                Text("EggSpend is locked")
                    .font(.title2.bold())
                    .foregroundStyle(Color.nestBrown)

                Text("Authenticate to view your finances.")
                    .font(.subheadline)
                    .foregroundStyle(Color.twig)

                Button {
                    Task { await controller.authenticate() }
                } label: {
                    Text(controller.authInFlight ? "Unlocking…" : "Unlock")
                        .frame(maxWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .tint(.yolk)
                .disabled(controller.authInFlight)
                .accessibilityLabel(controller.authInFlight ? "Unlocking" : "Unlock EggSpend")
            }
            .padding()
        }
    }
}
