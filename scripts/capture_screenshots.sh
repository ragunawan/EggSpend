#!/bin/bash
# Builds EggSpend, installs it on a given iOS Simulator, and captures the five
# primary App Store screenshots (Home, Transactions, Budget, Nest Egg, Metrics)
# using the app's --preview-data / --tab <index> launch arguments.
#
# Usage:
#   scripts/capture_screenshots.sh <simulator-udid> <output-dir> [target-width target-height]
#
# If target width/height are given, each screenshot is resized to that exact
# pixel size with `sips` to match App Store Connect's required dimensions
# (simulators rarely produce those dimensions natively).
set -euo pipefail

UDID="${1:?usage: capture_screenshots.sh <simulator-udid> <output-dir> [target-width target-height]}"
OUTDIR="${2:?usage: capture_screenshots.sh <simulator-udid> <output-dir> [target-width target-height]}"
TARGET_W="${3:-}"
TARGET_H="${4:-}"

BUNDLE_ID="dev.gnwn.EggSpend"
SCHEME="EggSpend"
PROJECT="EggSpend.xcodeproj"

cd "$(dirname "$0")/.."

xcrun simctl boot "$UDID" 2>/dev/null || true

xcodebuild build -project "$PROJECT" -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$UDID" -quiet

BUILT_PRODUCTS_DIR=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$UDID" -showBuildSettings 2>/dev/null \
  | awk -F ' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')
APP_PATH="$BUILT_PRODUCTS_DIR/EggSpend.app"

xcrun simctl uninstall "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP_PATH"

mkdir -p "$OUTDIR"

NAMES=(01-home 02-transactions 03-budget 04-net-worth 05-metrics)

for i in "${!NAMES[@]}"; do
  name="${NAMES[$i]}"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" --preview-data --tab "$i" >/dev/null
  sleep 3
  RAW="$OUTDIR/${name}.png"
  xcrun simctl io "$UDID" screenshot "$RAW" >/dev/null
  if [ -n "$TARGET_W" ] && [ -n "$TARGET_H" ]; then
    sips -z "$TARGET_H" "$TARGET_W" "$RAW" >/dev/null
  fi
  echo "captured $RAW"
done

xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
echo "Done: $OUTDIR"
