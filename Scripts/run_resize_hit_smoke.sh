#!/bin/bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly OUTPUT="${TMPDIR:-/tmp}/QuickNotesResizeHitSmoke"

swiftc \
    "$PROJECT_DIR/Sources/QuickNotes/Views/WindowResizeOverlay.swift" \
    "$SCRIPT_DIR/ResizeHitSmoke.swift" \
    -framework AppKit \
    -framework SwiftUI \
    -o "$OUTPUT"

"$OUTPUT"
