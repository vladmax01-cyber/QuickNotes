#!/bin/bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly OUTPUT="$(mktemp "${TMPDIR:-/tmp}/quick-notes-haptic-smoke.XXXXXX")"
trap 'rm -f "$OUTPUT"' EXIT

swiftc \
    "$PROJECT_DIR/Sources/QuickNotes/Services/InteractionHaptics.swift" \
    "$PROJECT_DIR/Scripts/HapticSmoke.swift" \
    -o "$OUTPUT"
"$OUTPUT"
