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
