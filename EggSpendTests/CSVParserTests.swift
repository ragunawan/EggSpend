import XCTest
@testable import EggSpend

final class CSVParserTests: XCTestCase {

    // MARK: - Raw row parsing

    func testParseSimpleCSV() {
        let (headers, rows) = CSVParser.parse("Date,Title,Amount\n1/1/2024,Coffee,4.50\n1/2/2024,Rent,1200")
        XCTAssertEqual(headers, ["Date", "Title", "Amount"])
        XCTAssertEqual(rows, [["1/1/2024", "Coffee", "4.50"], ["1/2/2024", "Rent", "1200"]])
    }

    func testParseEmptyTextReturnsEmpty() {
        let (headers, rows) = CSVParser.parse("")
        XCTAssertEqual(headers, [])
        XCTAssertEqual(rows, [])
    }

    func testParseHeaderOnlyReturnsNoRows() {
        let (headers, rows) = CSVParser.parse("Date,Title,Amount")
        XCTAssertEqual(headers, ["Date", "Title", "Amount"])
        XCTAssertEqual(rows, [])
    }

    func testParseStripsLeadingBOM() {
        let (headers, _) = CSVParser.parse("\u{FEFF}Date,Title,Amount\n1/1/2024,Coffee,4.50")
        XCTAssertEqual(headers, ["Date", "Title", "Amount"])
    }

    func testParseHandlesCRLFLineEndings() {
        let (headers, rows) = CSVParser.parse("Date,Title\r\n1/1/2024,Coffee\r\n1/2/2024,Rent")
        XCTAssertEqual(headers, ["Date", "Title"])
        XCTAssertEqual(rows, [["1/1/2024", "Coffee"], ["1/2/2024", "Rent"]])
    }

    func testParseHandlesBareCRLineEndings() {
        let (headers, rows) = CSVParser.parse("Date,Title\r1/1/2024,Coffee\r1/2/2024,Rent")
        XCTAssertEqual(headers, ["Date", "Title"])
        XCTAssertEqual(rows, [["1/1/2024", "Coffee"], ["1/2/2024", "Rent"]])
    }

    func testParseQuotedFieldWithEmbeddedComma() {
        let (_, rows) = CSVParser.parse("Title,Amount\n\"Coffee, Latte\",4.50")
        XCTAssertEqual(rows, [["Coffee, Latte", "4.50"]])
    }

    func testParseQuotedFieldWithEmbeddedNewline() {
        let (_, rows) = CSVParser.parse("Title,Notes\nCoffee,\"line1\nline2\"")
        XCTAssertEqual(rows, [["Coffee", "line1\nline2"]])
    }

    func testParseQuotedFieldWithEscapedQuotes() {
        let (_, rows) = CSVParser.parse("Title\n\"He said \"\"hi\"\"\"")
        XCTAssertEqual(rows, [["He said \"hi\""]])
    }

    func testParseTrimsWhitespaceAroundUnquotedFields() {
        let (_, rows) = CSVParser.parse("Title,Amount\n  Coffee  ,  4.50  ")
        XCTAssertEqual(rows, [["Coffee", "4.50"]])
    }

    func testParseSkipsBlankLines() {
        let (_, rows) = CSVParser.parse("Title,Amount\nCoffee,4.50\n\n\nRent,1200")
        XCTAssertEqual(rows, [["Coffee", "4.50"], ["Rent", "1200"]])
    }

    // MARK: - Date parsing

    func testParseDateSlashFormats() {
        XCTAssertNotNil(CSVParser.parseDate("01/15/2024"))
        XCTAssertNotNil(CSVParser.parseDate("1/5/2024"))
        XCTAssertNotNil(CSVParser.parseDate("01/15/24"))
        XCTAssertNotNil(CSVParser.parseDate("1/5/24"))
    }

    func testParseDateISOFormats() {
        XCTAssertNotNil(CSVParser.parseDate("2024-01-15"))
        XCTAssertNotNil(CSVParser.parseDate("2024/01/15"))
    }

    func testParseDateDayMonthYearFormats() {
        XCTAssertNotNil(CSVParser.parseDate("15/01/2024"))
        XCTAssertNotNil(CSVParser.parseDate("15-01-2024"))
    }

    func testParseDateMonthNameFormats() {
        XCTAssertNotNil(CSVParser.parseDate("Jan 15, 2024"))
        XCTAssertNotNil(CSVParser.parseDate("January 15, 2024"))
        XCTAssertNotNil(CSVParser.parseDate("15 Jan 2024"))
    }

    func testParseDateTrimsWhitespace() {
        XCTAssertNotNil(CSVParser.parseDate("  2024-01-15  "))
    }

    func testParseDateInvalidReturnsNil() {
        XCTAssertNil(CSVParser.parseDate("not a date"))
        XCTAssertNil(CSVParser.parseDate(""))
        XCTAssertNil(CSVParser.parseDate("13/40/2024"))
    }

    func testParseDateProducesExpectedComponents() throws {
        let date = try XCTUnwrap(CSVParser.parseDate("2024-03-07"))
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        XCTAssertEqual(comps.year, 2024)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 7)
    }

    // MARK: - Amount parsing

    func testParseAmountPlainNumber() {
        XCTAssertEqual(CSVParser.parseAmount("4.50"), 4.50)
        XCTAssertEqual(CSVParser.parseAmount("1200"), 1200)
    }

    func testParseAmountWithCurrencySymbols() {
        XCTAssertEqual(CSVParser.parseAmount("$4.50"), 4.50)
        XCTAssertEqual(CSVParser.parseAmount("€4.50"), 4.50)
        XCTAssertEqual(CSVParser.parseAmount("£4.50"), 4.50)
        XCTAssertEqual(CSVParser.parseAmount("¥4.50"), 4.50)
        XCTAssertEqual(CSVParser.parseAmount("₹4.50"), 4.50)
    }

    func testParseAmountWithThousandsSeparator() {
        XCTAssertEqual(CSVParser.parseAmount("$1,234.56"), 1234.56)
        XCTAssertEqual(CSVParser.parseAmount("1,200"), 1200)
    }

    func testParseAmountNegativeWithMinusSign() {
        XCTAssertEqual(CSVParser.parseAmount("-4.50"), -4.50)
        XCTAssertEqual(CSVParser.parseAmount("-$4.50"), -4.50)
    }

    func testParseAmountNegativeWithParentheses() {
        XCTAssertEqual(CSVParser.parseAmount("(4.50)"), -4.50)
        XCTAssertEqual(CSVParser.parseAmount("($1,234.56)"), -1234.56)
    }

    func testParseAmountWithWhitespace() {
        XCTAssertEqual(CSVParser.parseAmount("  4.50  "), 4.50)
    }

    func testParseAmountInvalidReturnsNil() {
        XCTAssertNil(CSVParser.parseAmount("not a number"))
        XCTAssertNil(CSVParser.parseAmount(""))
    }

    func testParseAmountSignVariants() {
        let cases: [(String, Double?)] = [
            ("(12.34)", -12.34),
            ("12.34-", -12.34),
            ("\u{2212}12.34", -12.34),   // unicode minus sign
            ("-12.34", -12.34),
            ("$1,234.56", 1234.56),
            ("($1,234.56)", -1234.56),
            ("12-34", nil),               // ambiguous embedded minus, safely rejected
            ("1.234,56", nil)             // EU decimal comma format, safely rejected (T5)
        ]
        for (input, expected) in cases {
            XCTAssertEqual(CSVParser.parseAmount(input), expected, "input: \(input)")
        }
    }

    // MARK: - Title normalization (duplicate detection)

    func testNormalizedTitleCaseAndWhitespace() {
        XCTAssertEqual(CSVParser.normalizedTitle("  Coffee   Shop  "), "coffee shop")
        XCTAssertEqual(CSVParser.normalizedTitle("COFFEE SHOP"), "coffee shop")
        XCTAssertEqual(CSVParser.normalizedTitle("Coffee\tShop\nDowntown"), "coffee shop downtown")
        XCTAssertEqual(CSVParser.normalizedTitle("Coffee Shop"), CSVParser.normalizedTitle("coffee   shop"))
    }

    // MARK: - Account type inference

    func testInferAccountTypeChecking() {
        XCTAssertEqual(CSVParser.inferAccountType(from: "Checking"), .checking)
        XCTAssertEqual(CSVParser.inferAccountType(from: "Current Account"), .checking)
    }

    func testInferAccountTypeSavings() {
        XCTAssertEqual(CSVParser.inferAccountType(from: "Savings"), .savings)
    }

    func testInferAccountTypeInvestment() {
        XCTAssertEqual(CSVParser.inferAccountType(from: "Investment"), .investment)
        XCTAssertEqual(CSVParser.inferAccountType(from: "Brokerage"), .investment)
        XCTAssertEqual(CSVParser.inferAccountType(from: "401k"), .investment)
        XCTAssertEqual(CSVParser.inferAccountType(from: "IRA"), .investment)
        XCTAssertEqual(CSVParser.inferAccountType(from: "Pension"), .investment)
    }

    func testInferAccountTypeCredit() {
        XCTAssertEqual(CSVParser.inferAccountType(from: "Credit Card"), .credit)
    }

    func testInferAccountTypeLoan() {
        XCTAssertEqual(CSVParser.inferAccountType(from: "Loan"), .loan)
        XCTAssertEqual(CSVParser.inferAccountType(from: "Mortgage"), .mortgage)
        XCTAssertEqual(CSVParser.inferAccountType(from: "Debt"), .loan)
    }

    func testInferAccountTypeUnknownFallsBackToOther() {
        XCTAssertEqual(CSVParser.inferAccountType(from: "Misc"), .other)
        XCTAssertEqual(CSVParser.inferAccountType(from: ""), .other)
    }

    // MARK: - Column auto-detection

    func testAutoDetectTransactionStandardHeaders() {
        let mapping = ColumnMapping.autoDetectTransaction(headers: ["Date", "Description", "Amount", "Category"])
        XCTAssertEqual(mapping.dateColumn, "Date")
        XCTAssertEqual(mapping.titleColumn, "Description")
        XCTAssertEqual(mapping.amountColumn, "Amount")
        XCTAssertEqual(mapping.categoryColumn, "Category")
    }

    func testAutoDetectTransactionIsCaseInsensitive() {
        let mapping = ColumnMapping.autoDetectTransaction(headers: ["DATE", "description", "AMOUNT"])
        XCTAssertEqual(mapping.dateColumn, "DATE")
        XCTAssertEqual(mapping.titleColumn, "description")
        XCTAssertEqual(mapping.amountColumn, "AMOUNT")
    }

    func testAutoDetectTransactionBankVariantHeaders() {
        let mapping = ColumnMapping.autoDetectTransaction(
            headers: ["Posted Date", "Original Description", "Transaction Amount", "Transaction Type", "Notes"]
        )
        XCTAssertEqual(mapping.dateColumn, "Posted Date")
        XCTAssertEqual(mapping.titleColumn, "Original Description")
        XCTAssertEqual(mapping.amountColumn, "Transaction Amount")
        XCTAssertEqual(mapping.typeColumn, "Transaction Type")
        XCTAssertEqual(mapping.notesColumn, "Notes")
    }

    func testAutoDetectTransactionMissingColumnsAreNil() {
        let mapping = ColumnMapping.autoDetectTransaction(headers: ["Foo", "Bar"])
        XCTAssertNil(mapping.dateColumn)
        XCTAssertNil(mapping.titleColumn)
        XCTAssertNil(mapping.amountColumn)
    }

    func testAutoDetectAccountStandardHeaders() {
        let mapping = ColumnMapping.autoDetectAccount(headers: ["Account Name", "Type", "Balance", "Notes"])
        XCTAssertEqual(mapping.nameColumn, "Account Name")
        XCTAssertEqual(mapping.acctTypeColumn, "Type")
        XCTAssertEqual(mapping.balanceColumn, "Balance")
        XCTAssertEqual(mapping.acctNotesColumn, "Notes")
    }

    // MARK: - Transaction row mapping

    func testParseTransactionRowsHappyPath() {
        let headers = ["Date", "Description", "Amount"]
        let mapping = ColumnMapping.autoDetectTransaction(headers: headers)
        let rows = [["1/15/2024", "Coffee", "4.50"], ["1/16/2024", "Salary", "3000"]]

        let results = CSVParser.parseTransactionRows(rows: rows, headers: headers, mapping: mapping)

        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results[0].isValid)
        XCTAssertEqual(results[0].title, "Coffee")
        XCTAssertEqual(results[0].amount, 4.50)
        XCTAssertNotNil(results[0].date)
        XCTAssertEqual(results[0].rowIndex, 2)
        XCTAssertEqual(results[1].rowIndex, 3)
    }

    func testParseTransactionRowsInfersExpenseFromNegativeAmount() {
        let headers = ["Date", "Description", "Amount"]
        var mapping = ColumnMapping.autoDetectTransaction(headers: headers)
        mapping.negativeIsExpense = true
        let rows = [["1/15/2024", "Coffee", "-4.50"], ["1/16/2024", "Salary", "3000"]]

        let results = CSVParser.parseTransactionRows(rows: rows, headers: headers, mapping: mapping)

        XCTAssertEqual(results[0].type, .expense)
        XCTAssertEqual(results[0].amount, 4.50, "amount should be stored as a positive magnitude")
        XCTAssertEqual(results[1].type, .income)
    }

    func testParseTransactionRowsInfersTypeFromTypeColumnKeywords() {
        let headers = ["Date", "Description", "Amount", "Type"]
        let mapping = ColumnMapping.autoDetectTransaction(headers: headers)
        let rows = [
            ["1/15/2024", "Coffee", "4.50", "Debit"],
            ["1/16/2024", "Refund", "4.50", "Credit"],
            ["1/17/2024", "Card payment", "20", "Charge"],
            ["1/18/2024", "ATM", "20", "Withdrawal"]
        ]

        let results = CSVParser.parseTransactionRows(rows: rows, headers: headers, mapping: mapping)

        XCTAssertEqual(results[0].type, .expense)
        XCTAssertEqual(results[1].type, .income)
        XCTAssertEqual(results[2].type, .expense)
        XCTAssertEqual(results[3].type, .expense)
    }

    func testParseTransactionRowsInfersTypeFromKeywordsTableDriven() {
        let headers = ["Date", "Description", "Amount", "Type"]
        let mapping = ColumnMapping.autoDetectTransaction(headers: headers)
        let cases: [(String, TransactionType)] = [
            ("Purchase", .expense),
            ("Payment", .expense),
            ("POS", .expense),
            ("Deposit", .income),
            ("Direct Deposit", .income),
            ("Credit", .income),
            ("Refund", .income),
            ("DR", .expense),
            ("CR", .income)
        ]
        for (typeValue, expected) in cases {
            let rows = [["1/15/2024", "Row", "4.50", typeValue]]
            let results = CSVParser.parseTransactionRows(rows: rows, headers: headers, mapping: mapping)
            XCTAssertEqual(results[0].type, expected, "type column: \(typeValue)")
        }
    }

    func testParseTransactionRowsUnknownTypeFallsBackToAmountSign() {
        let headers = ["Date", "Description", "Amount", "Type"]
        let mapping = ColumnMapping.autoDetectTransaction(headers: headers)

        let expenseRows = [["1/15/2024", "Row", "-50", "xyz"]]
        let expenseResults = CSVParser.parseTransactionRows(rows: expenseRows, headers: headers, mapping: mapping)
        XCTAssertEqual(expenseResults[0].type, .expense)

        let incomeRows = [["1/15/2024", "Row", "50", "xyz"]]
        let incomeResults = CSVParser.parseTransactionRows(rows: incomeRows, headers: headers, mapping: mapping)
        XCTAssertEqual(incomeResults[0].type, .income)
    }

    func testParseTransactionRowsMissingTitleUsesRowFallback() {
        // The fallback "Row N" placeholder is written into `title` before `isValid`
        // evaluates it, so a row with a blank title column is not flagged invalid
        // here (unlike a result whose title is cleared after parsing, e.g. in the
        // edit UI, which would hit the "Missing title" validation path).
        let headers = ["Date", "Description", "Amount"]
        let mapping = ColumnMapping.autoDetectTransaction(headers: headers)
        let rows = [["1/15/2024", "", "4.50"]]

        let results = CSVParser.parseTransactionRows(rows: rows, headers: headers, mapping: mapping)

        XCTAssertEqual(results[0].title, "Row 2")
        XCTAssertTrue(results[0].isValid)
        XCTAssertNil(results[0].validationError)
    }

    func testParseTransactionRowsInvalidDateProducesValidationError() {
        let headers = ["Date", "Description", "Amount"]
        let mapping = ColumnMapping.autoDetectTransaction(headers: headers)
        let rows = [["not a date", "Coffee", "4.50"]]

        let results = CSVParser.parseTransactionRows(rows: rows, headers: headers, mapping: mapping)

        XCTAssertFalse(results[0].isValid)
        XCTAssertEqual(results[0].validationError, "Invalid date")
    }

    func testParseTransactionRowsInvalidAmountProducesValidationError() {
        let headers = ["Date", "Description", "Amount"]
        let mapping = ColumnMapping.autoDetectTransaction(headers: headers)
        let rows = [["1/15/2024", "Coffee", "garbage"]]

        let results = CSVParser.parseTransactionRows(rows: rows, headers: headers, mapping: mapping)

        XCTAssertFalse(results[0].isValid)
        XCTAssertEqual(results[0].validationError, "Invalid amount")
    }

    func testParseTransactionRowsEmptyCategoryIsNil() {
        let headers = ["Date", "Description", "Amount", "Category"]
        let mapping = ColumnMapping.autoDetectTransaction(headers: headers)
        let rows = [["1/15/2024", "Coffee", "4.50", ""]]

        let results = CSVParser.parseTransactionRows(rows: rows, headers: headers, mapping: mapping)

        XCTAssertNil(results[0].categoryName)
    }

    func testParseTransactionRowsUnmappedColumnYieldsEmptyField() {
        let headers = ["Date", "Description", "Amount"]
        var mapping = ColumnMapping.autoDetectTransaction(headers: headers)
        mapping.categoryColumn = nil

        let rows = [["1/15/2024", "Coffee", "4.50"]]
        let results = CSVParser.parseTransactionRows(rows: rows, headers: headers, mapping: mapping)

        XCTAssertNil(results[0].categoryName)
    }

    // MARK: - Account row mapping

    func testParseAccountRowsHappyPath() {
        let headers = ["Account Name", "Type", "Balance"]
        let mapping = ColumnMapping.autoDetectAccount(headers: headers)
        let rows = [["Chase Checking", "Checking", "1500.25"], ["Visa", "Credit Card", "-300"]]

        let results = CSVParser.parseAccountRows(rows: rows, headers: headers, mapping: mapping)

        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results[0].isValid)
        XCTAssertEqual(results[0].name, "Chase Checking")
        XCTAssertEqual(results[0].type, .checking)
        XCTAssertEqual(results[0].balance, 1500.25)
        XCTAssertEqual(results[1].type, .credit)
        XCTAssertEqual(results[1].balance, -300)
    }

    func testParseAccountRowsMissingNameUsesRowFallback() {
        // As with transaction rows, the "Row N" placeholder is written into `name`
        // before `isValid` evaluates it, so a blank name column does not fail
        // validation through this path as long as the balance parses.
        let headers = ["Account Name", "Type", "Balance"]
        let mapping = ColumnMapping.autoDetectAccount(headers: headers)
        let rows = [["", "Checking", "1500"]]

        let results = CSVParser.parseAccountRows(rows: rows, headers: headers, mapping: mapping)

        XCTAssertEqual(results[0].name, "Row 2")
        XCTAssertTrue(results[0].isValid)
        XCTAssertNil(results[0].validationError)
    }

    func testParseAccountRowsInvalidBalanceProducesValidationError() {
        let headers = ["Account Name", "Type", "Balance"]
        let mapping = ColumnMapping.autoDetectAccount(headers: headers)
        let rows = [["Chase Checking", "Checking", "garbage"]]

        let results = CSVParser.parseAccountRows(rows: rows, headers: headers, mapping: mapping)

        XCTAssertFalse(results[0].isValid)
        XCTAssertEqual(results[0].validationError, "Invalid balance")
    }

    func testParseAccountRowsUnknownTypeFallsBackToOther() {
        let headers = ["Account Name", "Type", "Balance"]
        let mapping = ColumnMapping.autoDetectAccount(headers: headers)
        let rows = [["Misc Account", "Something Else", "100"]]

        let results = CSVParser.parseAccountRows(rows: rows, headers: headers, mapping: mapping)

        XCTAssertEqual(results[0].type, .other)
    }

    // MARK: - End-to-end

    func testFullPipelineFromRawCSVToParsedTransactions() {
        let csv = """
        Date,Description,Amount,Category
        1/15/2024,"Coffee, Latte",-4.50,Dining
        1/16/2024,Salary,3000.00,
        """
        let (headers, rows) = CSVParser.parse(csv)
        let mapping = ColumnMapping.autoDetectTransaction(headers: headers)
        let results = CSVParser.parseTransactionRows(rows: rows, headers: headers, mapping: mapping)

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].title, "Coffee, Latte")
        XCTAssertEqual(results[0].type, .expense)
        XCTAssertEqual(results[0].amount, 4.50)
        XCTAssertEqual(results[0].categoryName, "Dining")
        XCTAssertEqual(results[1].type, .income)
        XCTAssertNil(results[1].categoryName)
    }
}
