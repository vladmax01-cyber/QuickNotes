#!/bin/bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly SWIFTLINT="/Volumes/SSK Drive/Applications/Developer Tools/SwiftLint/0.65.1/swiftlint"

if [[ ! -x "$SWIFTLINT" ]]; then
    echo "SwiftLint is unavailable. Connect SSK Drive and retry: $SWIFTLINT" >&2
    exit 69
fi

echo "Building Quick Notes (release)..."
swift build --package-path "$PROJECT_DIR" --configuration release

echo "Checking Swift source with SwiftLint..."
"$SWIFTLINT" lint \
    --config "$PROJECT_DIR/.swiftlint.yml" \
    --working-directory "$PROJECT_DIR" \
    --disable-sourcekit \
    --strict \
    --no-cache \
    --quiet

echo "Running isolated smoke tests..."
for suite in core model rich_text content_features format_visual haptic palette_placement resize_hit contrast; do
    bash "$SCRIPT_DIR/run_${suite}_smoke.sh"
done

echo "Quick Notes verification passed."
