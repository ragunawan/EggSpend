import XCTest
@testable import EggSpend

final class CurrencyFormatTests: XCTestCase {

    override func tearDownWithError() throws {
        // Mutable static leaks across tests — always reset.
        CurrencyFormat.override = nil
        try super.tearDownWithError()
    }

    // MARK: - code(locale:)

    func testCodeEnUS() {
        XCTAssertEqual(CurrencyFormat.code(locale: Locale(identifier: "en_US")), "USD")
    }

    func testCodeDeDE() {
        XCTAssertEqual(CurrencyFormat.code(locale: Locale(identifier: "de_DE")), "EUR")
    }

    func testCodeJaJP() {
        XCTAssertEqual(CurrencyFormat.code(locale: Locale(identifier: "ja_JP")), "JPY")
    }

    // MARK: - symbol(locale:)

    func testSymbolEnUS() {
        XCTAssertEqual(CurrencyFormat.symbol(locale: Locale(identifier: "en_US")), "$")
    }

    func testSymbolDeDE() {
        XCTAssertEqual(CurrencyFormat.symbol(locale: Locale(identifier: "de_DE")), "€")
    }

    func testSymbolJaJP() {
        // ja_JP's real Locale.currencySymbol (ICU ground truth), not a Western assumption.
        XCTAssertEqual(CurrencyFormat.symbol(locale: Locale(identifier: "ja_JP")), "¥")
    }

    // MARK: - override

    func testOverrideWinsOverLocale() {
        CurrencyFormat.override = "GBP"
        XCTAssertEqual(CurrencyFormat.code(locale: Locale(identifier: "en_US")), "GBP")
        XCTAssertEqual(CurrencyFormat.code(locale: Locale(identifier: "de_DE")), "GBP")
    }

    // symbol(locale:) must honor override too, or the 78 amount displays (via code)
    // and the 9 input-field "$" prefixes (via symbol) would disagree once a future
    // Settings toggle sets an override. ICU ground truth (verified via `swift -e`):
    // NumberFormatter(locale: en_US, currencyCode: "GBP").currencySymbol == "£".
    func testSymbolRespectsOverride() {
        CurrencyFormat.override = "GBP"
        XCTAssertEqual(CurrencyFormat.symbol(locale: Locale(identifier: "en_US")), "£")
    }

    // MARK: - money(_:locale:)

    func testMoneyEnUSUsesDollarSignAndDotDecimal() {
        let text = CurrencyFormat.money(1234.5, locale: Locale(identifier: "en_US"))
        XCTAssertTrue(text.contains("$"), text)
        XCTAssertTrue(text.contains("1,234.50"), text)
    }

    func testMoneyDeDEUsesEuroAndCommaSeparator() {
        // ICU ground truth for de_DE EUR formatting of 1234.5 is "1.234,50\u{00A0}€"
        // (a regular no-break space, not the narrow U+202F some other locales use) —
        // verified via `swift -e` rather than assumed. Assert on the digit/separator
        // substrings and the symbol, not the exact whitespace byte.
        let text = CurrencyFormat.money(1234.5, locale: Locale(identifier: "de_DE"))
        XCTAssertTrue(text.contains("1.234,50"), text)
        XCTAssertTrue(text.contains("€"), text)
    }

    func testMoneyJaJPUsesYenAndNoDecimals() {
        // JPY has zero minor units, so ICU ground truth for 1234.5 rounds to "¥1,234".
        let text = CurrencyFormat.money(1234.5, locale: Locale(identifier: "ja_JP"))
        XCTAssertTrue(text.contains("¥"), text)
        XCTAssertTrue(text.contains("1,234"), text)
    }

    func testMoneyRespectsOverride() {
        CurrencyFormat.override = "GBP"
        let text = CurrencyFormat.money(10, locale: Locale(identifier: "en_US"))
        XCTAssertTrue(text.contains("£") || text.contains("GBP"), text)
    }
}
