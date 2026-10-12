#!/bin/bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/quick-notes-model.XXXXXX")"
trap 'rm -rf -- "$TEMP_DIR"' EXIT

swiftc \
    -emit-library \
    -emit-module \
    -module-name QuickNotesCore \
    "$PROJECT_DIR"/Sources/QuickNotesCore/*.swift \
    -o "$TEMP_DIR/libQuickNotesCore.dylib"

swiftc \
    "$PROJECT_DIR/Sources/QuickNotes/Models/NotesStore.swift" \
    "$PROJECT_DIR/Sources/QuickNotes/Models/AppPreferences.swift" \
    "$PROJECT_DIR/Sources/QuickNotes/MenuBar/MenuBarController.swift" \
    "$SCRIPT_DIR/ModelSmoke.swift" \
    -I "$TEMP_DIR" \
    -L "$TEMP_DIR" \
    -lQuickNotesCore \
    -Xlinker -rpath \
    -Xlinker "$TEMP_DIR" \
    -o "$TEMP_DIR/model-smoke"

"$TEMP_DIR/model-smoke"
