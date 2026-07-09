import XCTest
@testable import EggSpend

final class AmountParserTests: XCTestCase {

    // MARK: - en_US

    func testEnUSPlainDecimal() {
        XCTAssertEqual(AmountParser.parse("12.50", locale: Locale(identifier: "en_US")), 12.50)
    }

    func testEnUSGroupedThousands() {
        XCTAssertEqual(AmountParser.parse("1,234.56", locale: Locale(identifier: "en_US")), 1234.56)
    }

    // Regression pin: a comma NOT in a valid thousands position (only 2 digits follow it)
    // must be rejected, not silently misread as 1250 — restores the old safe rejection.
    func testEnUSMisplacedGroupingSeparatorReturnsNil() {
        XCTAssertNil(AmountParser.parse("12,50", locale: Locale(identifier: "en_US")))
    }

    // Trailing-separator leniency is intentionally NOT supported: a stray separator
    // with nothing after it is rejected, since it's ambiguous/malformed input.
    func testEnUSTrailingGroupingSeparatorReturnsNil() {
        XCTAssertNil(AmountParser.parse("12,", locale: Locale(identifier: "en_US")))
    }

    // MARK: - fr_FR

    func testFrFRCommaDecimal() {
        XCTAssertEqual(AmountParser.parse("12,50", locale: Locale(identifier: "fr_FR")), 12.50)
    }

    func testFrFRGroupedThousandsWithDot() {
        // fr_FR's decimal separator is "," so a "." in the integer part is treated as
        // a grouping separator; here it sits in a valid 3-digit thousands position.
        XCTAssertEqual(AmountParser.parse("1.234,56", locale: Locale(identifier: "fr_FR")), 1234.56)
    }

    func testFrFRGroupedThousandsWithRegularSpace() {
        // Real Foundation/ICU fr_FR grouping typically uses a (narrow) no-break space,
        // not ".", but a plain space is also accepted as a grouping candidate.
        XCTAssertEqual(AmountParser.parse("1 234,56", locale: Locale(identifier: "fr_FR")), 1234.56)
    }

    func testFrFRGroupedThousandsWithNarrowNoBreakSpace() {
        XCTAssertEqual(AmountParser.parse("1\u{202F}234,56", locale: Locale(identifier: "fr_FR")), 1234.56)
    }

    func testFrFRTrailingSeparatorReturnsNil() {
        XCTAssertNil(AmountParser.parse("12,", locale: Locale(identifier: "fr_FR")))
    }

    // Ambiguity pin: a literal dot always parses as a plain decimal first, even
    // though "." can be a fr_FR grouping separator — "1.234" must mean 1.234, not 1234.
    func testFrFRLiteralDotWinsOverGrouping() {
        XCTAssertEqual(AmountParser.parse("1.234", locale: Locale(identifier: "fr_FR")), 1.234)
    }

    // MARK: - de_DE

    func testDeDECommaDecimal() {
        XCTAssertEqual(AmountParser.parse("12,50", locale: Locale(identifier: "de_DE")), 12.50)
    }

    func testDeDEGroupedThousands() {
        XCTAssertEqual(AmountParser.parse("1.234,56", locale: Locale(identifier: "de_DE")), 1234.56)
    }

    // MARK: - Invalid / edge input

    func testEmptyStringReturnsNil() {
        XCTAssertNil(AmountParser.parse(""))
    }

    func testWhitespaceOnlyReturnsNil() {
        XCTAssertNil(AmountParser.parse("   "))
    }

    func testLoneDotReturnsNil() {
        XCTAssertNil(AmountParser.parse("."))
    }

    func testLoneMinusReturnsNil() {
        XCTAssertNil(AmountParser.parse("-"))
    }

    func testNegativeAmount() {
        XCTAssertEqual(AmountParser.parse("-12.50", locale: Locale(identifier: "en_US")), -12.50)
    }

    // MARK: - Round-trip with FormatStyle pre-fill

    func testRoundTripFormattedThenParsed() {
        let locales = [Locale(identifier: "en_US"), Locale(identifier: "fr_FR"), Locale(identifier: "de_DE")]
        let value = 1234.5
        for locale in locales {
            // .grouping(.never) so the round-trip text never exercises the strict
            // thousands-grouping validation — this test is about the decimal separator.
            let style = FloatingPointFormatStyle<Double>(locale: locale)
                .precision(.fractionLength(2))
                .grouping(.never)
            let text = value.formatted(style)
            let parsed = AmountParser.parse(text, locale: locale)
            XCTAssertNotNil(parsed, "locale \(locale.identifier) failed to round-trip \(text)")
            XCTAssertEqual(parsed ?? -1, value, accuracy: 0.001, "locale \(locale.identifier)")
        }
    }
}
