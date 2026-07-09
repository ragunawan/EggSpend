import Foundation

/// Locale-tolerant parsing for money text fields fed by `.decimalPad` keyboards.
///
/// Decimal-pad users can end up with either `.` or `,` as their decimal mark
/// depending on region, so this is deliberately permissive about the decimal
/// separator. It is, however, deliberately *strict* about thousands grouping:
/// a grouping character is only accepted when it sits in a valid thousands
/// position (first group 1-3 digits, every subsequent group exactly 3 digits).
/// This avoids a 100x parsing hazard — e.g. a pasted `"12,50"` under `en_US`
/// (comma isn't a valid grouping position there: only 2 digits follow it) is
/// rejected rather than silently read as `1250`.
enum AmountParser {
    /// Grouping separators actually seen in the wild across locales: ASCII period/comma,
    /// a regular space, the no-break space (U+00A0), and the narrow no-break space (U+202F,
    /// used by many European locales including `fr_FR` for thousands grouping).
    private static let allGroupingCandidates: Set<Character> = [".", ",", " ", "\u{00A0}", "\u{202F}"]

    /// Parses user-entered amount text into a `Double`, tolerating both `.`-decimal
    /// and locale-decimal (e.g. `,` in `fr_FR`/`de_DE`) input, plus locale-appropriate
    /// thousands grouping. Returns `nil` for empty/whitespace-only or otherwise
    /// unparseable/ambiguous text.
    ///
    /// - Note on ambiguity: a literal string that already parses as a plain `.`-decimal
    ///   `Double` (e.g. `"1.234"`, or a bare integer like `"1234"`) is always tried
    ///   *first*, regardless of locale. Under `fr_FR`, `.` is normally a grouping
    ///   separator, which would make `"1.234"` mean 1234; instead we deliberately
    ///   parse it as 1.234. Decimal-pad entry rarely if ever needs a thousands
    ///   grouping separator, so treating a bare dot as "always decimal" is safer
    ///   for money entry than guessing at locale-correct grouping.
    /// - Note on strict grouping / no trailing-separator leniency: the fallback path
    ///   only accepts a grouping character when it is followed by exactly 3 digits
    ///   (the standard thousands-grouping position). This means malformed grouping
    ///   like `"12,50"` under `en_US` (2 digits after the comma) or a trailing
    ///   separator like `"12,"` (0 digits after it, under any locale) is rejected
    ///   as `nil` rather than leniently accepted — a stray or misplaced separator
    ///   should block Save, not silently mis-parse the amount.
    static func parse(_ text: String, locale: Locale = .current) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Literal fast-path parse always wins first (see ambiguity note above).
        if let value = Double(trimmed) {
            return value
        }

        let decimalSeparator = locale.decimalSeparator ?? ","
        guard !decimalSeparator.isEmpty else { return nil }

        // At most one decimal separator occurrence is allowed.
        let decimalOccurrences = trimmed.components(separatedBy: decimalSeparator).count - 1
        guard decimalOccurrences <= 1 else { return nil }

        let parts = trimmed.components(separatedBy: decimalSeparator)
        let integerPart = parts[0]
        let fractionPart = parts.count > 1 ? parts[1] : nil

        // A decimal separator with nothing after it (e.g. "12,") is rejected, not
        // leniently treated as a whole number.
        if let fractionPart {
            guard !fractionPart.isEmpty, fractionPart.allSatisfy({ $0.isNumber }) else { return nil }
        }

        let groupingCandidates = allGroupingCandidates.subtracting(
            decimalSeparator.first.map { [$0] } ?? []
        )
        guard let normalizedInteger = validatedInteger(integerPart, groupingCandidates: groupingCandidates) else {
            return nil
        }

        let normalized = fractionPart.map { "\(normalizedInteger).\($0)" } ?? normalizedInteger
        return Double(normalized)
    }

    /// Validates thousands-grouping positions in an integer-part string and, if valid,
    /// returns it with all grouping characters removed. Returns `nil` if any grouping
    /// character sits outside a valid thousands position.
    private static func validatedInteger(_ integerPart: String, groupingCandidates: Set<Character>) -> String? {
        guard !integerPart.isEmpty else { return nil }

        var segments: [String] = [""]
        for character in integerPart {
            if groupingCandidates.contains(character) {
                segments.append("")
            } else if character.isNumber {
                segments[segments.count - 1].append(character)
            } else {
                return nil // stray character that's neither a digit nor a recognized grouping separator
            }
        }

        if segments.count > 1 {
            // A separator was present: first group is 1-3 digits, every group after it
            // must be exactly 3 digits (standard thousands-grouping positions).
            guard !segments[0].isEmpty, segments[0].count <= 3 else { return nil }
            for segment in segments[1...] {
                guard segment.count == 3 else { return nil }
            }
        } else {
            // No separator at all — any run of digits is fine (grouping is optional).
            guard !segments[0].isEmpty else { return nil }
        }

        return segments.joined()
    }
}
