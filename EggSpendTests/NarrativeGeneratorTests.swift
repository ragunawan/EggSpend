import XCTest
@testable import EggSpend

/// Deterministic stub for `NarrativeModelSession` — the live model is
/// unavailable in CI and, even where available, its output is
/// non-deterministic, so every generation test injects this instead.
final class StubNarrativeModelSession: NarrativeModelSession, @unchecked Sendable {
    enum Behavior {
        case respond(String)
        case throwError
    }

    private struct StubError: Error {}

    private let behavior: Behavior
    private(set) var callCount = 0

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    func respond(to prompt: String) async throws -> String {
        callCount += 1
        switch behavior {
        case .respond(let text):
            return text
        case .throwError:
            throw StubError()
        }
    }
}

final class NarrativeGeneratorTests: XCTestCase {

    private let sentence = NarrativeGenerator.Sentence(
        text: "Dining is $120 above your usual pace.",
        figures: ["$120"]
    )

    // MARK: - isAvailable (pure gating predicate)

    func testIsAvailableTrueForAvailable() {
        XCTAssertTrue(NarrativeGenerator.isAvailable(availability: { .available }))
    }

    func testIsAvailableFalseForDeviceNotEligible() {
        XCTAssertFalse(NarrativeGenerator.isAvailable(availability: { .unavailable(.deviceNotEligible) }))
    }

    func testIsAvailableFalseForAppleIntelligenceNotEnabled() {
        XCTAssertFalse(NarrativeGenerator.isAvailable(availability: { .unavailable(.appleIntelligenceNotEnabled) }))
    }

    func testIsAvailableFalseForModelNotReady() {
        XCTAssertFalse(NarrativeGenerator.isAvailable(availability: { .unavailable(.modelNotReady) }))
    }

    // MARK: - generate: availability gating (session must never be touched)

    func testGenerateReturnsNilAndSkipsSessionWhenDeviceNotEligible() async {
        let session = StubNarrativeModelSession(behavior: .respond("should never be seen"))
        let result = await NarrativeGenerator.generate(
            sentences: [sentence], session: session, availability: { .unavailable(.deviceNotEligible) }
        )
        XCTAssertNil(result)
        XCTAssertEqual(session.callCount, 0)
    }

    func testGenerateReturnsNilAndSkipsSessionWhenAppleIntelligenceNotEnabled() async {
        let session = StubNarrativeModelSession(behavior: .respond("should never be seen"))
        let result = await NarrativeGenerator.generate(
            sentences: [sentence], session: session, availability: { .unavailable(.appleIntelligenceNotEnabled) }
        )
        XCTAssertNil(result)
        XCTAssertEqual(session.callCount, 0)
    }

    func testGenerateReturnsNilAndSkipsSessionWhenModelNotReady() async {
        let session = StubNarrativeModelSession(behavior: .respond("should never be seen"))
        let result = await NarrativeGenerator.generate(
            sentences: [sentence], session: session, availability: { .unavailable(.modelNotReady) }
        )
        XCTAssertNil(result)
        XCTAssertEqual(session.callCount, 0)
    }

    func testGenerateReturnsNilAndSkipsSessionWhenSentencesEmpty() async {
        let session = StubNarrativeModelSession(behavior: .respond("should never be seen"))
        let result = await NarrativeGenerator.generate(sentences: [], session: session, availability: { .available })
        XCTAssertNil(result)
        XCTAssertEqual(session.callCount, 0)
    }

    // MARK: - generate: happy path

    func testGenerateReturnsRewrittenTextWhenFiguresPreserved() async {
        let session = StubNarrativeModelSession(
            behavior: .respond("Heads up — dining ran $120 over your usual pace this month.")
        )
        let result = await NarrativeGenerator.generate(sentences: [sentence], session: session, availability: { .available })
        XCTAssertEqual(result, "Heads up — dining ran $120 over your usual pace this month.")
        XCTAssertEqual(session.callCount, 1)
    }

    // MARK: - generate: figure-drop path

    func testGenerateReturnsNilWhenExpectedFigureIsDropped() async {
        let session = StubNarrativeModelSession(behavior: .respond("Dining ran a bit over your usual pace this month."))
        let result = await NarrativeGenerator.generate(sentences: [sentence], session: session, availability: { .available })
        XCTAssertNil(result)
    }

    // MARK: - generate: thrown-error path

    func testGenerateReturnsNilWhenSessionThrows() async {
        let session = StubNarrativeModelSession(behavior: .throwError)
        let result = await NarrativeGenerator.generate(sentences: [sentence], session: session, availability: { .available })
        XCTAssertNil(result)
    }

    // MARK: - generate: hallucinated-figure path (model keeps the real figure
    // but also invents a new one — no existing test above would have caught
    // this before `preservesFigures` started rejecting extra numeric tokens)

    func testGenerateReturnsNilWhenModelAddsExtraNumberAlongsidePreservedFigure() async {
        let session = StubNarrativeModelSession(
            behavior: .respond("Dining ran $120 over — about 15% more than last month.")
        )
        let result = await NarrativeGenerator.generate(sentences: [sentence], session: session, availability: { .available })
        XCTAssertNil(result)
    }

    // MARK: - preservesFigures

    func testPreservesFiguresTrueWhenAllFiguresPresent() {
        XCTAssertTrue(NarrativeGenerator.preservesFigures("Dining is $120 over this month.", expectedFigures: ["$120"]))
    }

    func testPreservesFiguresFalseWhenAFigureIsMissing() {
        XCTAssertFalse(NarrativeGenerator.preservesFigures("Dining ran high this month.", expectedFigures: ["$120"]))
    }

    func testPreservesFiguresFalseWhenOnlySomeFiguresPresent() {
        XCTAssertFalse(
            NarrativeGenerator.preservesFigures("Dining is $120 over, groceries are fine.", expectedFigures: ["$120", "$45"])
        )
    }

    func testPreservesFiguresTrueWhenExpectedFiguresEmpty() {
        XCTAssertTrue(NarrativeGenerator.preservesFigures("any text at all", expectedFigures: []))
    }

    // The figure is present, but the model also invented an unrelated
    // percentage — the whole output must be rejected, not just partially
    // accepted, since any hallucinated figure is unacceptable.
    func testPreservesFiguresFalseWhenOutputContainsUnexpectedExtraNumber() {
        XCTAssertFalse(
            NarrativeGenerator.preservesFigures(
                "Dining ran $120 over — about 15% more than last month.",
                expectedFigures: ["$120"]
            )
        )
    }

    func testPreservesFiguresFalseWhenOutputContainsUnexpectedPercentage() {
        XCTAssertFalse(
            NarrativeGenerator.preservesFigures("You're up 12% this month.", expectedFigures: [])
        )
    }

    // A figure repeated verbatim (e.g. restated for emphasis) is fine — the
    // check is set membership, not occurrence count.
    func testPreservesFiguresTrueWhenExpectedFigureAppearsTwice() {
        XCTAssertTrue(
            NarrativeGenerator.preservesFigures("$120 over — yes, $120 over your usual pace.", expectedFigures: ["$120"])
        )
    }

    func testPreservesFiguresTrueWhenCommaGroupedFigurePreservedExactly() {
        XCTAssertTrue(
            NarrativeGenerator.preservesFigures("You're $1,234.56 over this month.", expectedFigures: ["$1,234.56"])
        )
    }

    func testPreservesFiguresFalseWhenCommaGroupedFigureIsAltered() {
        // Off by a single cent — must not slip through as "close enough".
        XCTAssertFalse(
            NarrativeGenerator.preservesFigures("You're $1,234.57 over this month.", expectedFigures: ["$1,234.56"])
        )
    }

    // With no expected figures at all, any number appearing in the output is
    // itself the hallucination — there is nothing legitimate for it to be.
    func testPreservesFiguresFalseWhenExpectedFiguresEmptyButOutputContainsNumber() {
        XCTAssertFalse(NarrativeGenerator.preservesFigures("Spending is up $50 this month.", expectedFigures: []))
    }

    // MARK: - numericTokens

    func testNumericTokensExtractsCurrencyGroupedDecimalAsSingleToken() {
        XCTAssertEqual(NarrativeGenerator.numericTokens(in: "You're $1,234.56 over."), ["$1,234.56"])
    }

    func testNumericTokensExtractsPercentage() {
        XCTAssertEqual(NarrativeGenerator.numericTokens(in: "Up 15% this month."), ["15%"])
    }

    func testNumericTokensIgnoresOrdinaryPunctuation() {
        XCTAssertEqual(NarrativeGenerator.numericTokens(in: "Hello, world."), [])
    }

    // MARK: - makePrompt / instructions (prompt-construction contract)

    func testMakePromptContainsEverySentenceText() {
        let sentences = [
            sentence,
            NarrativeGenerator.Sentence(text: "Groceries is $45 below your usual pace.", figures: ["$45"])
        ]
        let prompt = NarrativeGenerator.makePrompt(sentences: sentences)
        XCTAssertTrue(prompt.contains("Dining is $120 above your usual pace."))
        XCTAssertTrue(prompt.contains("Groceries is $45 below your usual pace."))
    }

    func testInstructionsRequirePreservingFiguresVerbatim() {
        let instructions = NarrativeGenerator.instructions.lowercased()
        XCTAssertTrue(instructions.contains("preserve"))
        XCTAssertTrue(instructions.contains("number"))
    }
}
