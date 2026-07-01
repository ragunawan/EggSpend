# EggSpend

A SwiftUI personal finance app for tracking transactions, budgets, accounts, and net worth.

<p align="center">
  <img src="screenshots/iphone-6.3/01-home.png" width="200" alt="Home" />
  <img src="screenshots/iphone-6.3/02-transactions.png" width="200" alt="Transactions" />
  <img src="screenshots/iphone-6.3/03-budget.png" width="200" alt="Budget" />
  <img src="screenshots/iphone-6.3/04-net-worth.png" width="200" alt="Net Worth" />
</p>

## Features

- Transaction tracking with CSV import
- Accounts and account balances
- Budgets with category-based tracking
- Recurring transactions
- Cash-flow forecasts (30/60/90-day projections)
- Spending metrics and monthly review
- Net worth / nest egg tracking
- Savings goals

## Stack

- Swift 6, SwiftUI, SwiftData
- CloudKit-backed `ModelContainer` with automatic local fallback (no iCloud sign-in required)
- iOS Simulator / Xcode workflow

## Getting Started

```bash
open EggSpend.xcodeproj
```

Or build and test from the command line:

```bash
# Build
xcodebuild build -project EggSpend.xcodeproj -scheme EggSpend -destination 'platform=iOS Simulator,name=iPhone 17'

# Run all tests
xcodebuild test -project EggSpend.xcodeproj -scheme EggSpend -destination 'platform=iOS Simulator,name=iPhone 17'
```

Useful launch arguments (set in the Xcode scheme or via `ProcessInfo`):

- `--preview-data` — seeds sample transactions, accounts, and budgets on launch
- `--tab <index>` — opens a specific root tab: `0` Home, `1` Transactions, `2` Budget, `3` Nest Egg, `4` Metrics

## Repository Structure

- `EggSpend/` — app source
  - `Models/` — SwiftData models (`Transaction`, `TransactionCategory`, `Account`, `Budget`, `RecurringTransaction`)
  - `Views/` — SwiftUI feature screens (Accounts, Budget, Categories, Dashboard, Forecast, Import, Metrics, NetWorth, Recurring, Transactions, SafeSpend, SavingsGoals, MonthlyReview)
  - `Persistence/` — `ModelContainer` setup and default data seeding
  - `Utilities/` — shared logic (`CSVParser`, `AccountBalanceService`, `MonthlyReviewCalculator`)
  - `EggSpendTheme.swift` — shared colors, gradients, and view modifiers
- `EggSpendTests/` — XCTest coverage for models, metrics, budgets, forecasting, and more
- `generate_project.py` — generates `EggSpend.xcodeproj/project.pbxproj`; keep in sync when adding/removing Swift files
- `docs/` — GitHub Pages site (privacy policy, support page)
- `screenshots/` — App Store screenshot sets

## Contributing

See [CLAUDE.md](CLAUDE.md) for architecture notes and development conventions.

## Support

Questions, bug reports, or feedback: [ryan@gnwn.dev](mailto:ryan@gnwn.dev). See also the [support page](docs/support.md) and [privacy policy](docs/app-store-privacy.md).
