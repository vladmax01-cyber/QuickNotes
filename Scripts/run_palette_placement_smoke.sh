#!/bin/bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly OUTPUT="${TMPDIR:-/tmp}/QuickNotesPalettePlacementSmoke"

swiftc \
    "$PROJECT_DIR/Sources/QuickNotes/Views/FormattingPalettePlacement.swift" \
    "$SCRIPT_DIR/PalettePlacementSmoke.swift" \
    -framework AppKit \
    -o "$OUTPUT"

"$OUTPUT"
