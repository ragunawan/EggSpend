import Foundation

// MARK: – Raw CSV parsing (RFC 4180 compliant)

enum CSVParser {
    /// Parses CSV text into (headers, dataRows). Handles quoted fields, escaped
    /// quotes, \r\n / \n line endings, and a leading UTF-8 BOM.
    static func parse(_ rawText: String) -> (headers: [String], rows: [[String]]) {
        var text = rawText
        // Strip UTF-8 BOM if present
        if text.hasPrefix("\u{FEFF}") { text = String(text.dropFirst()) }
        // Normalize CRLF to LF. Swift treats "\r\n" as a single grapheme cluster,
        // so the per-character scan below would otherwise never match it as a line break.
        text = text.replacingOccurrences(of: "\r\n", with: "\n")

        let allRows = parseRows(text)
        guard let header = allRows.first else { return ([], []) }
        return (header, Array(allRows.dropFirst()))
    }

    private static func parseRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var row:   [String] = []
        var inQuotes = false
        var i = text.startIndex

        while i < text.endIndex {
            let ch = text[i]
            if inQuotes {
                if ch == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex && text[next] == "\"" {
                        field.append("\"")         // escaped ""
                        i = text.index(after: next)
                        continue
                    }
                    inQuotes = false
                } else {
                    field.append(ch)
                }
            } else {
                switch ch {
                case "\"":
                    inQuotes = true
                case ",":
                    row.append(field.trimmingCharacters(in: .whitespaces))
                    field = ""
                case "\r", "\n":
                    row.append(field.trimmingCharacters(in: .whitespaces))
                    field = ""
                    if !row.allSatisfy(\.isEmpty) { rows.append(row) }
                    row = []
                    if ch == "\r" {
                        let next = text.index(after: i)
                        if next < text.endIndex && text[next] == "\n" { i = next }
                    }
                default:
                    field.append(ch)
                }
            }
            i = text.index(after: i)
        }
        row.append(field.trimmingCharacters(in: .whitespaces))
        if !row.allSatisfy(\.isEmpty) { rows.append(row) }
        return rows
    }
}

// MARK: – Field parsing helpers

extension CSVParser {
    /// Tries multiple date formats common in bank exports.
    static func parseDate(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        let formats = [
            "MM/dd/yyyy", "M/d/yyyy", "MM/dd/yy", "M/d/yy",
            "yyyy-MM-dd", "yyyy/MM/dd",
            "dd/MM/yyyy", "d/M/yyyy",
            "dd-MM-yyyy", "d-M-yyyy",
            "MMM d, yyyy", "MMMM d, yyyy",
            "dd MMM yyyy", "d MMM yyyy"
        ]
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        for f in formats {
            fmt.dateFormat = f
            if let date = fmt.date(from: s) { return date }
        }
        return nil
    }

    /// Strips currency symbols and thousand separators, handles parentheses for negatives.
    static func parseAmount(_ raw: String) -> Double? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        // Detect sign first, on the original trimmed string: parens, leading, or trailing minus.
        let negative = (s.hasPrefix("(") && s.hasSuffix(")"))
            || s.hasPrefix("-") || s.hasPrefix("−")
            || s.hasSuffix("-") || s.hasSuffix("−")
        // Strip currency symbols / parens / spaces, but not minus signs (handled separately below).
        for sym in ["$", "€", "£", "¥", "₹", "(", ")", " "] {
            s = s.replacingOccurrences(of: sym, with: "")
        }
        // Remove a single leading and/or trailing minus sign.
        if s.hasPrefix("-") || s.hasPrefix("−") { s.removeFirst() }
        if s.hasSuffix("-") || s.hasSuffix("−") { s.removeLast() }
        // Any remaining minus sign means this isn't a valid signed number (e.g. "12-34").
        if s.contains("-") || s.contains("−") { return nil }
        // Remove thousand-separator commas (keep decimal point)
        let parts = s.components(separatedBy: ".")
        if parts.count <= 2 {
            s = parts[0].replacingOccurrences(of: ",", with: "")
            if parts.count == 2 { s += "." + parts[1] }
        }
        guard let value = Double(s), value >= 0 else { return nil }
        return negative ? -value : value
    }

    static func inferAccountType(from raw: String) -> AccountType {
        let s = raw.lowercased()
        if s.contains("checking") || s.contains("current")         { return .checking }
        if s.contains("saving")                                     { return .savings }
        if s.contains("investment") || s.contains("brokerage")
            || s.contains("401") || s.contains("ira")
            || s.contains("pension")                                { return .investment }
        if s.contains("credit")                                     { return .credit }
        if s.contains("loan") || s.contains("mortgage")
            || s.contains("debt")                                   { return .loan }
        return .other
    }
}

// MARK: – Column mapping

struct ColumnMapping {
    // Transactions
    var dateColumn:     String? = nil
    var titleColumn:    String? = nil
    var amountColumn:   String? = nil
    var typeColumn:     String? = nil
    var categoryColumn: String? = nil
    var notesColumn:    String? = nil
    var negativeIsExpense: Bool = true   // if no typeColumn: negative amount → expense

    // Accounts
    var nameColumn:        String? = nil
    var acctTypeColumn:    String? = nil
    var balanceColumn:     String? = nil
    var acctNotesColumn:   String? = nil

    // Auto-detect common bank/Mint/Apple Card CSV headers
    static func autoDetectTransaction(headers: [String]) -> ColumnMapping {
        var m = ColumnMapping()
        func pick(_ candidates: [String]) -> String? {
            candidates.first { c in headers.first { $0.lowercased() == c } != nil }
                .flatMap { c in headers.first { $0.lowercased() == c } }
        }
        m.dateColumn     = pick(["transaction date","date","posted date","post date","clearing date","trans date"])
        m.titleColumn    = pick(["description","original description","payee","merchant","memo","name","narrative","details"])
        m.amountColumn   = pick(["amount","amount (usd)","transaction amount","debit amount","credit amount","sum","value"])
        m.typeColumn     = pick(["transaction type","type","credit/debit"])
        m.categoryColumn = pick(["category","merchant category"])
        m.notesColumn    = pick(["notes","memo","labels","note","comment","remarks"])
        return m
    }

    static func autoDetectAccount(headers: [String]) -> ColumnMapping {
        var m = ColumnMapping()
        func pick(_ candidates: [String]) -> String? {
            candidates.first { c in headers.first { $0.lowercased() == c } != nil }
                .flatMap { c in headers.first { $0.lowercased() == c } }
        }
        m.nameColumn      = pick(["account name","name","account","description"])
        m.acctTypeColumn  = pick(["type","account type","kind"])
        m.balanceColumn   = pick(["balance","current balance","amount","value"])
        m.acctNotesColumn = pick(["notes","note","memo","comment"])
        return m
    }
}

// MARK: – Parsed result types

struct ParsedTransactionResult: Identifiable {
    let id = UUID()
    let rowIndex: Int
    var title: String
    var date:   Date?
    var amount: Double?
    var type:   TransactionType
    var categoryName: String?
    var notes:  String

    var isValid: Bool {
        date != nil && amount != nil && !title.trimmingCharacters(in: .whitespaces).isEmpty
    }
    var validationError: String? {
        if title.trimmingCharacters(in: .whitespaces).isEmpty { return "Missing title" }
        if date   == nil { return "Invalid date" }
        if amount == nil { return "Invalid amount" }
        return nil
    }
}

struct ParsedAccountResult: Identifiable {
    let id = UUID()
    let rowIndex: Int
    var name:    String
    var type:    AccountType
    var balance: Double?
    var notes:   String

    var isValid: Bool {
        balance != nil && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }
    var validationError: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Missing name" }
        if balance == nil { return "Invalid balance" }
        return nil
    }
}

// MARK: – Row → domain object

extension CSVParser {
    static func parseTransactionRows(
        rows: [[String]],
        headers: [String],
        mapping: ColumnMapping
    ) -> [ParsedTransactionResult] {
        func field(_ col: String?, in row: [String]) -> String {
            guard let col, let idx = headers.firstIndex(of: col), idx < row.count else { return "" }
            return row[idx]
        }

        return rows.enumerated().compactMap { idx, row in
            let title  = field(mapping.titleColumn,    in: row)
            let rawDate = field(mapping.dateColumn,    in: row)
            let rawAmt  = field(mapping.amountColumn,  in: row)
            let rawType = field(mapping.typeColumn,    in: row).lowercased()
            let catName = field(mapping.categoryColumn, in: row)
            let notes   = field(mapping.notesColumn,   in: row)

            let amount = parseAmount(rawAmt)
            let date   = parseDate(rawDate)

            // Determine income/expense. rawType is already lowercased above.
            // Expense keywords are checked first: "payment" can misfire on statements
            // like "Payment Received" (an income event) — accepted v1 imprecision.
            let expenseKeywords = ["debit", "expense", "charge", "withdrawal", "purchase", "sale", "payment", "pos", "dr"]
            let incomeKeywords  = ["income", "deposit", "refund", "credit", "cr"]
            // "pos"/"dr"/"cr" are short enough to collide as substrings of other
            // keywords (e.g. "pos" inside "deposit"), so they must match whole words only.
            let shortKeywords: Set<String> = ["pos", "dr", "cr"]
            let tokens = Set(rawType.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
            func matches(_ keyword: String) -> Bool {
                shortKeywords.contains(keyword) ? tokens.contains(keyword) : rawType.contains(keyword)
            }
            let txType: TransactionType
            if expenseKeywords.contains(where: matches) {
                txType = .expense
            } else if incomeKeywords.contains(where: matches) {
                txType = .income
            } else if let a = amount {
                txType = (a < 0) == mapping.negativeIsExpense ? .expense : .income
            } else {
                txType = .expense
            }

            return ParsedTransactionResult(
                rowIndex:     idx + 2,   // 1-based, row 1 is header
                title:        title.isEmpty ? "Row \(idx + 2)" : title,
                date:         date,
                amount:       amount.map { abs($0) },
                type:         txType,
                categoryName: catName.isEmpty ? nil : catName,
                notes:        notes
            )
        }
    }

    static func parseAccountRows(
        rows: [[String]],
        headers: [String],
        mapping: ColumnMapping
    ) -> [ParsedAccountResult] {
        func field(_ col: String?, in row: [String]) -> String {
            guard let col, let idx = headers.firstIndex(of: col), idx < row.count else { return "" }
            return row[idx]
        }

        return rows.enumerated().compactMap { idx, row in
            let name    = field(mapping.nameColumn,      in: row)
            let rawType = field(mapping.acctTypeColumn,  in: row)
            let rawBal  = field(mapping.balanceColumn,   in: row)
            let notes   = field(mapping.acctNotesColumn, in: row)

            return ParsedAccountResult(
                rowIndex: idx + 2,
                name:     name.isEmpty ? "Row \(idx + 2)" : name,
                type:     inferAccountType(from: rawType),
                balance:  parseAmount(rawBal),
                notes:    notes
            )
        }
    }
}
