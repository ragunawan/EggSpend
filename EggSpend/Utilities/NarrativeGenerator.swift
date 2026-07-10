import Foundation
import FoundationModels

/// On-device tone-rewriting for template sentences (e.g.
/// `SpendingDeltaCalculator.CategoryDelta.sentence`), built on Apple's
/// `FoundationModels` framework (iOS 26+, on-device only by design — the
/// framework never makes a network call, so no explicit network-avoidance
/// code is needed here or anywhere downstream of it).
///
/// Contract:
/// - **Numbers always come from the calculators, never the model.** Every
///   call site supplies its already-computed template sentences plus the
///   literal figure substrings within them (currency amounts, percentages,
///   etc.); the model is instructed to rewrite tone only and preserve every
///   figure character-for-character. `generate(sentences:session:availability:)`
///   enforces this two ways before ever returning a narrative: every expected
///   figure must still be present verbatim, **and** every number-like token
///   found anywhere in the model's output must be one of the expected figures
///   — a rewrite that keeps the real figure but also invents an extra one
///   (e.g. a hallucinated "15%" alongside the real dollar amount) is rejected
///   just as surely as one that drops the real figure. See `preservesFigures`.
/// - **Template sentences are the always-works path.** This engine returns
///   `nil` whenever the model is unavailable, the session throws, or the
///   output fails figure validation (a dropped, altered, or invented figure)
///   — callers must fall back to the original `Sentence.text` values (joined)
///   in every `nil` case. This engine never returns a narrative that fails
///   figure validation.
/// - **Availability is environment-dependent, not just OS-version-dependent.**
///   Raising the deployment target to iOS 26 makes the framework importable
///   everywhere the app runs, but `SystemLanguageModel.default.availability`
///   still varies per device/simulator: CI simulators typically report
///   `.unavailable` (no Apple Intelligence in a CI runner), while this dev
///   machine's simulator reports `.available` via host-Mac Apple Intelligence
///   passthrough (observed 2026-07-10). Never assume availability — always
///   gate on the live check.
///
/// This file is a pure engine: no SwiftData, no `@Model`, no view code, no
/// `print`/logging of the figures it handles (they're financial amounts).
enum NarrativeGenerator {

    /// One template sentence plus the literal figure substrings within it
    /// that must survive a tone-rewrite unchanged (e.g. `"Dining is $120
    /// above your usual pace."` paired with `["$120"]`). Deliberately not
    /// bound to `SpendingDeltaCalculator.CategoryDelta` — any future
    /// template-sentence surface (Monthly Review, etc.) can supply its own.
    struct Sentence {
        let text: String
        let figures: [String]
    }

    /// Instructions given to the model session. Callers construct their
    /// session with this text (e.g. `LiveNarrativeModelSession(instructions:
    /// NarrativeGenerator.instructions)`) — `generate` itself only ever sends
    /// the sentence prompt, not the instructions, to keep the session
    /// reusable and the prompt-construction contract independently testable.
    static let instructions = """
    You rewrite short personal-finance summary sentences in a warmer, more \
    conversational tone. Preserve every number, dollar amount, and \
    percentage exactly as written, character for character — never add, \
    remove, round, or alter a figure. Keep each rewrite brief, at most one \
    sentence per input line, and introduce no new numbers.
    """

    /// Joins `sentences` into the literal prompt sent to the model session.
    /// Pure and testable independent of any live session.
    static func makePrompt(sentences: [Sentence]) -> String {
        sentences.map(\.text).joined(separator: "\n")
    }

    /// Extracts every number-like token from `text`: an optional currency
    /// symbol, one or more digits/grouping commas, an optional decimal
    /// fraction, and an optional trailing percent sign — e.g. `"$1,234.56"`,
    /// `"120"`, `"15%"` each extract as a single token. Requires a leading
    /// digit (immediately after the optional currency symbol) so ordinary
    /// punctuation such as a sentence comma is never mistaken for a token.
    ///
    /// Used by `preservesFigures` to catch not just a *dropped* figure but an
    /// *invented* one — a number the model introduced that the calculators
    /// never produced. Deliberately conservative: an incidental quantity in
    /// the model's rewrite (e.g. the "3" in "over the last 3 months") also
    /// counts as a token and must itself appear in `expectedFigures` or the
    /// whole output is rejected. That false-positive risk is intentional —
    /// this validator's one job is zero tolerance for hallucinated financial
    /// figures, per the "numbers always come from the calculators, never the
    /// model" rule.
    static func numericTokens(in text: String) -> [String] {
        let pattern = #"\p{Sc}?\d[\d,]*(?:\.\d+)?%?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        return matches.map { nsText.substring(with: $0.range) }
    }

    /// True iff `output` (a) contains every figure in `expectedFigures`
    /// verbatim, and (b) contains no number-like token (per `numericTokens`)
    /// that isn't one of `expectedFigures` — i.e. the set of numbers found in
    /// `output` is a subset of `expectedFigures`. Both directions matter: (a)
    /// alone would miss a model that keeps the real figure but bolts on an
    /// invented one; (b) alone would miss a model that silently drops a
    /// figure entirely. A repeated figure is fine (sets, not counts).
    ///
    /// An empty `expectedFigures` list only passes when `output` contains no
    /// numbers at all — a number appearing from nowhere is exactly the
    /// hallucination case this function exists to reject, even with nothing
    /// to compare it against.
    static func preservesFigures(_ output: String, expectedFigures: [String]) -> Bool {
        guard expectedFigures.allSatisfy({ output.contains($0) }) else { return false }
        let expectedSet = Set(expectedFigures)
        let foundTokens = Set(numericTokens(in: output))
        return foundTokens.isSubset(of: expectedSet)
    }

    /// Pure availability gate over `SystemLanguageModel.Availability` — takes
    /// an injectable provider (defaulting to the live framework check) so it
    /// is testable against every case without touching `FoundationModels` at
    /// all.
    static func isAvailable(
        availability: () -> SystemLanguageModel.Availability = { SystemLanguageModel.default.availability }
    ) -> Bool {
        if case .available = availability() { return true }
        return false
    }

    /// Attempts an on-device tone rewrite of `sentences` via `session`.
    /// Returns `nil` (never a partial/invalid result) when:
    /// - the model is unavailable (per `isAvailable`), or `sentences` is empty,
    /// - `session.respond(to:)` throws,
    /// - the response fails `preservesFigures` — it drops an expected figure,
    ///   alters one, or introduces any number-like token that isn't one of
    ///   the expected figures.
    ///
    /// Callers must render the original template sentences whenever this
    /// returns `nil` — that fallback path is what keeps the feature
    /// "always works" per the spec.
    static func generate(
        sentences: [Sentence],
        session: NarrativeModelSession,
        availability: () -> SystemLanguageModel.Availability = { SystemLanguageModel.default.availability }
    ) async -> String? {
        guard isAvailable(availability: availability), !sentences.isEmpty else { return nil }

        let expectedFigures = sentences.flatMap(\.figures)
        let prompt = makePrompt(sentences: sentences)

        do {
            let output = try await session.respond(to: prompt)
            return preservesFigures(output, expectedFigures: expectedFigures) ? output : nil
        } catch {
            return nil
        }
    }
}

/// Seam over `LanguageModelSession` so tests can inject a deterministic stub
/// — the live model is unavailable in CI and, even where available, its
/// output is non-deterministic.
protocol NarrativeModelSession: Sendable {
    func respond(to prompt: String) async throws -> String
}

/// Live implementation backed by `FoundationModels.LanguageModelSession`.
/// `LanguageModelSession` is `@unchecked Sendable` and its `respond(to:)` is
/// `nonisolated(nonsending)`, so it is safely callable directly from
/// `@MainActor` call sites with no `Task.detached` needed.
struct LiveNarrativeModelSession: NarrativeModelSession {
    private let session: LanguageModelSession

    init(instructions: String) {
        session = LanguageModelSession(instructions: instructions)
    }

    func respond(to prompt: String) async throws -> String {
        let response = try await session.respond(to: prompt)
        return response.content
    }
}
