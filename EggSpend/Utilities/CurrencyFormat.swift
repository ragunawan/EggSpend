import Foundation

/// Central, single override point for the app's display currency (display-only,
/// per product decision — no per-record/stored currency).
enum CurrencyFormat {
    /// Set by a future Settings toggle. nil (default) = derive from locale.
    nonisolated(unsafe) static var override: String?

    static func code(locale: Locale = .current) -> String {
        override ?? locale.currency?.identifier ?? "USD"
    }
    static var code: String { code() }

    static func symbol(locale: Locale = .current) -> String {
        // Must honor `override` too — otherwise once a future Settings toggle sets
        // it, the 78 amount displays (which all route through `code`) and the 9
        // input-field prefixes (which route through `symbol`) would disagree.
        guard let override else { return locale.currencySymbol ?? "$" }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.currencyCode = override
        return formatter.currencySymbol ?? override
    }
    static var symbol: String { symbol() }

    static func style(locale: Locale = .current) -> FloatingPointFormatStyle<Double>.Currency {
        // `.currency(code:)` alone doesn't carry a locale — FormatStyle.formatted()
        // otherwise falls back to .autoupdatingCurrent for separators, ignoring the
        // `locale` parameter here. Pin it explicitly so grouping/decimal separators
        // actually follow the requested locale, not just the currency code.
        .currency(code: code(locale: locale)).locale(locale)
    }

    static func money(_ value: Double, locale: Locale = .current) -> String {
        value.formatted(style(locale: locale))
    }
}
