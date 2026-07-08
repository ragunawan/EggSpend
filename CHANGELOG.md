# Changelog

## Unreleased

- Added App Store encryption compliance metadata declaring no non-exempt encryption.
- Fixed a bug where net worth in the Metrics timeline and Monthly Review was computed by adding liability balances instead of subtracting them, inflating reported net worth; introduced a shared `NetWorthCalculator` now used consistently by Dashboard, Nest Egg, Metrics, and Monthly Review, and Metrics/Monthly Review now respect the "include in net worth" account setting.
- Added GitHub Actions CI workflow (`.github/workflows/test.yml`) with runtime simulator resolution and artifact capture; tests now run on macOS runners for all PRs and pushes to main and claude/* branches.
- Fixed historical net-worth reconstruction in Metrics timeline and Monthly Review to only include account-linked transactions; account-less (unlinked) transactions are now excluded from retroactive net worth calculations, respecting the "include in net worth" account setting consistently.
- Fixed CSV import amount and transaction-type parsing: `parseAmount` now detects sign indicators (parentheses, leading/trailing minus, U+2212) before stripping whitespace and rejects embedded minuses; CSV type inference now uses expense/income keyword lists with amount-sign fallback for unknown types, applying whole-word token matching to short keywords (pos/dr/cr) to prevent false matches like "pos" in "Deposit".
- Fixed recurring transaction materialization for ended items: items that have reached their end date but still have overdue occurrences between nextDueDate and endDate now materialize those final transactions instead of being silently skipped. Also added an infinite-loop guard that halts materialization if `advanceNextDueDate()` fails to strictly advance the date, preventing hangs when the Calendar API returns nil.
