import XCTest
@testable import EggSpend

/// Deterministic, immediate-outcome stub for `BiometricAuthenticating` — the
/// live `LAContext` prompt is Simulator-manual-only (see IMPLEMENTATION_PLAN.md
/// T20 notes), so every state-machine test injects this instead. Mirrors
/// `StubNarrativeModelSession`'s precedent for a similarly untestable-live
/// API surface.
final class StubBiometricAuthenticator: BiometricAuthenticating, @unchecked Sendable {
    enum Outcome {
        case succeed
        case fail
        case throwError
    }

    private struct StubError: Error {}

    private let outcome: Outcome
    private let canEvaluateResult: Bool
    private(set) var evaluateCallCount = 0

    init(outcome: Outcome = .succeed, canEvaluateResult: Bool = true) {
        self.outcome = outcome
        self.canEvaluateResult = canEvaluateResult
    }

    func canEvaluate() -> Bool { canEvaluateResult }

    func evaluate(reason: String) async throws -> Bool {
        evaluateCallCount += 1
        switch outcome {
        case .succeed: return true
        case .fail: return false
        case .throwError: throw StubError()
        }
    }
}

/// Suspension-controllable stub — `evaluate(reason:)` hangs until the test
/// explicitly resolves it via `resumeSucceed()`, letting a test deterministically
/// observe `authInFlight` mid-attempt without relying on `Task.sleep` timing.
/// Used only by the double-trigger test below. `@MainActor`-isolated (matching
/// `AppLockController`) so `evaluateCallCount`'s mutation is serialized on the
/// same executor as the test's polling loop — without this, `evaluate(reason:)`
/// would run its call-count increment on a different executor than the
/// `authInFlight` flag it races against, making the poll observe `authInFlight`
/// before the increment is guaranteed visible.
@MainActor
final class BlockingBiometricAuthenticator: BiometricAuthenticating, @unchecked Sendable {
    private(set) var evaluateCallCount = 0
    private var pendingContinuation: CheckedContinuation<Bool, Error>?

    nonisolated func canEvaluate() -> Bool { true }

    func evaluate(reason: String) async throws -> Bool {
        evaluateCallCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            pendingContinuation = continuation
        }
    }

    func resumeSucceed() {
        pendingContinuation?.resume(returning: true)
        pendingContinuation = nil
    }
}

@MainActor
final class AppLockControllerTests: XCTestCase {

    // MARK: - Cold launch pre-arming

    func testColdLaunchPreArmedWhenLockEnabled() {
        let controller = AppLockController(authenticator: StubBiometricAuthenticator(), lockEnabled: { true })
        XCTAssertTrue(controller.isLocked)
    }

    func testColdLaunchNotArmedWhenLockDisabled() {
        let controller = AppLockController(authenticator: StubBiometricAuthenticator(), lockEnabled: { false })
        XCTAssertFalse(controller.isLocked)
    }

    // MARK: - Background arming

    func testBackgroundArmsWhenEnabled() async {
        // Start from an unlocked, foregrounded session (distinct from the
        // cold-launch pre-arm case above) to prove backgrounding itself
        // re-arms the lock, not just initial construction.
        let stub = StubBiometricAuthenticator(outcome: .succeed)
        let controller = AppLockController(authenticator: stub, lockEnabled: { true })
        await controller.authenticate()
        XCTAssertFalse(controller.isLocked)

        controller.sceneDidEnterBackground()
        XCTAssertTrue(controller.isLocked)
    }

    func testBackgroundNoOpWhenDisabled() {
        let controller = AppLockController(authenticator: StubBiometricAuthenticator(), lockEnabled: { false })
        controller.sceneDidEnterBackground()
        XCTAssertFalse(controller.isLocked)
    }

    // MARK: - Active triggers authentication

    func testActiveTriggersExactlyOneEvaluateWhenLocked() async {
        let stub = StubBiometricAuthenticator()
        let controller = AppLockController(authenticator: stub, lockEnabled: { true })
        XCTAssertTrue(controller.isLocked)
        await controller.sceneDidBecomeActive()
        XCTAssertEqual(stub.evaluateCallCount, 1)
        XCTAssertFalse(controller.isLocked)
    }

    func testActiveDoesNothingWhenNotLocked() async {
        let stub = StubBiometricAuthenticator()
        let controller = AppLockController(authenticator: stub, lockEnabled: { false })
        XCTAssertFalse(controller.isLocked)
        await controller.sceneDidBecomeActive()
        XCTAssertEqual(stub.evaluateCallCount, 0)
    }

    func testActiveWithAuthInFlightDoesNotDoubleTrigger() async {
        let stub = BlockingBiometricAuthenticator()
        let controller = AppLockController(authenticator: stub, lockEnabled: { true })
        XCTAssertTrue(controller.isLocked)

        let firstAttempt = Task { await controller.sceneDidBecomeActive() }
        // Wait for the first attempt to actually be in flight before firing
        // the second trigger, so the race is deterministic rather than timing-based.
        while !controller.authInFlight {
            await Task.yield()
        }

        // A second trigger (e.g. the lock cover's own on-appear) while the
        // first attempt is still pending must not start a second challenge.
        await controller.sceneDidBecomeActive()
        XCTAssertEqual(stub.evaluateCallCount, 1)

        stub.resumeSucceed()
        await firstAttempt.value
        XCTAssertFalse(controller.isLocked)
        XCTAssertFalse(controller.authInFlight)
    }

    // MARK: - authenticate() outcomes

    func testSuccessUnlocksAndResetsAuthInFlight() async {
        let stub = StubBiometricAuthenticator(outcome: .succeed)
        let controller = AppLockController(authenticator: stub, lockEnabled: { true })
        await controller.authenticate()
        XCTAssertFalse(controller.isLocked)
        XCTAssertFalse(controller.authInFlight)
    }

    func testFailureStaysLockedAndResetsAuthInFlight() async {
        let stub = StubBiometricAuthenticator(outcome: .fail)
        let controller = AppLockController(authenticator: stub, lockEnabled: { true })
        await controller.authenticate()
        XCTAssertTrue(controller.isLocked)
        XCTAssertFalse(controller.authInFlight)
    }

    func testThrownErrorStaysLockedAndResetsAuthInFlight() async {
        // canEvaluateResult defaults to true — a normal failed/cancelled
        // attempt on a device that still has device-owner auth configured
        // must NOT unlock. Distinct from the recovery case below.
        let stub = StubBiometricAuthenticator(outcome: .throwError, canEvaluateResult: true)
        let controller = AppLockController(authenticator: stub, lockEnabled: { true })
        await controller.authenticate()
        XCTAssertTrue(controller.isLocked)
        XCTAssertFalse(controller.authInFlight)
    }

    // MARK: - Permanent-lockout recovery: canEvaluate() re-check on throw

    func testThrownErrorWithNoDeviceAuthConfiguredUnlocksAsRecovery() async {
        // If the device has lost all device-owner auth capability (e.g. the
        // user removed their passcode after enabling the lock, which also
        // disables biometrics), every future evaluate() call throws
        // forever, and Settings — the only off-switch — is itself behind
        // this lock. App-level security can never exceed OS-level
        // security: canEvaluate() reporting false must auto-unlock rather
        // than trap the user out of their own data.
        let stub = StubBiometricAuthenticator(outcome: .throwError, canEvaluateResult: false)
        let controller = AppLockController(authenticator: stub, lockEnabled: { true })
        await controller.authenticate()
        XCTAssertFalse(controller.isLocked)
        XCTAssertFalse(controller.authInFlight)
    }

    // MARK: - .inactive is deliberately never wired (documentation test)

    func testNoTransitionOccursWithoutAnExplicitMethodCall() {
        // There is intentionally no "scene did become inactive" method on
        // AppLockController — .inactive fires during the Face ID prompt
        // itself, so wiring it to arm/disarm would re-lock around the
        // prompt meant to clear it. This test documents that omission:
        // simply constructing the controller and doing nothing else never
        // changes its state on its own.
        let controller = AppLockController(authenticator: StubBiometricAuthenticator(), lockEnabled: { true })
        XCTAssertTrue(controller.isLocked)
        XCTAssertFalse(controller.authInFlight)
    }

    // MARK: - End-to-end: disabled setting never locks

    func testDisabledNeverLocksEndToEnd() async {
        let stub = StubBiometricAuthenticator()
        let controller = AppLockController(authenticator: stub, lockEnabled: { false })
        XCTAssertFalse(controller.isLocked)
        controller.sceneDidEnterBackground()
        XCTAssertFalse(controller.isLocked)
        await controller.sceneDidBecomeActive()
        XCTAssertFalse(controller.isLocked)
        XCTAssertEqual(stub.evaluateCallCount, 0)
    }

    // MARK: - Toggle-off-while-locked unlocks immediately

    func testToggleOffWhileLockedUnlocksImmediately() {
        var enabled = true
        let controller = AppLockController(authenticator: StubBiometricAuthenticator(), lockEnabled: { enabled })
        XCTAssertTrue(controller.isLocked)

        enabled = false
        controller.refreshForLockSettingChange()
        XCTAssertFalse(controller.isLocked)
    }

    func testRefreshForLockSettingChangeIsNoOpWhenStillEnabled() {
        let controller = AppLockController(authenticator: StubBiometricAuthenticator(), lockEnabled: { true })
        XCTAssertTrue(controller.isLocked)
        controller.refreshForLockSettingChange()
        XCTAssertTrue(controller.isLocked)
    }
}
