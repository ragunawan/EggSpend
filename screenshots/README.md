# Screenshots

App Store screenshot sets are grouped by device class.

- `iphone-6.3/` - 1206 x 2622 portrait screenshots, captured from an iPhone 17 Pro Max simulator and resized for App Store Connect.
- `ipad-13/` - 2064 x 2752 portrait screenshots, captured from an iPad Pro 13-inch simulator.

Primary upload order:

1. `01-home.png`
2. `02-transactions.png`
3. `03-budget.png`
4. `04-net-worth.png`
5. `05-metrics.png`

Files prefixed with `alternates-` are optional variants and are not part of the primary upload order.

## Refresh Workflow

The capture script builds the app, installs it on the requested simulator, launches each primary tab with preview data, and writes the five PNGs in upload order.

```bash
scripts/capture_screenshots.sh <simulator-udid> screenshots/iphone-6.3 1206 2622
scripts/capture_screenshots.sh <simulator-udid> screenshots/ipad-13 2064 2752
```

Preview data is enabled with `--preview-data`; the selected tab is controlled with `--tab 0...4`.

## Refresh Needed

The current PNGs were captured at commit `c635781` (2026-07-13). Since then, several visible UI changes have landed that are not yet reflected in these images:

- Settings reorganized into coherent sections (fixed a missing account-import icon)
- Quick Add keypad fills digits from the right; fixed a duplicate drag indicator and a clipped numpad
- Multiple Metrics/Budget/Nest Egg/Income & Expenses chart rendering fixes (axis gutters, tooltip text, selection-callout clipping, trajectory line colors/legend)
- Budget detail stat tiles no longer hide their titles
- Savings goal card progress bar now clips to the card's rounded corners; transfers can now be tagged as a savings goal contribution
- Tapping an account in Nest Egg now opens its transaction list; swipe-to-edit added for asset accounts
- Monthly Review empty state, animated value transitions, and accessibility labels

Re-run the capture script on a Mac with Xcode 26.6 and an iPhone 17 / iPad Pro 13" simulator to refresh both sets:

```bash
scripts/capture_screenshots.sh <simulator-udid> screenshots/iphone-6.3 1206 2622
scripts/capture_screenshots.sh <simulator-udid> screenshots/ipad-13 2064 2752
```

This repository checkout has no Xcode/Simulator toolchain available, so the images above could not be regenerated as part of this documentation update — only this note and the doc/onboarding text changes were made.
