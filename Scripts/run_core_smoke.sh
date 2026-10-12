#!/bin/bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/quick-notes-smoke.XXXXXX")"
trap 'rm -rf -- "$TEMP_DIR"' EXIT

swiftc \
    "$PROJECT_DIR"/Sources/QuickNotesCore/*.swift \
    "$SCRIPT_DIR/CoreSmoke.swift" \
    -o "$TEMP_DIR/core-smoke"

"$TEMP_DIR/core-smoke"
