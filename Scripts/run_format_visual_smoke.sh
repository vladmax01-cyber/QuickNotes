#!/bin/bash
set -euo pipefail
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly OUTPUT="${TMPDIR:-/tmp}/QuickNotesFormatVisualSmoke"
swiftc "$PROJECT_DIR/Sources/QuickNotes/Views/FormatControlGlyph.swift" \
    "$SCRIPT_DIR/FormatVisualSmoke.swift" -framework AppKit -framework SwiftUI -o "$OUTPUT"
"$OUTPUT"
