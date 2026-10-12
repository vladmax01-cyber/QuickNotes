#!/bin/bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/quick-notes-hotkey.XXXXXX")"
trap 'rm -rf -- "$TEMP_DIR"' EXIT

swiftc \
    -emit-library \
    -emit-module \
    -module-name QuickNotesCore \
    "$PROJECT_DIR/Sources/QuickNotesCore/ShortcutDefinition.swift" \
    -o "$TEMP_DIR/libQuickNotesCore.dylib"

swiftc \
    "$PROJECT_DIR/Sources/QuickNotes/Services/GlobalHotKeyService.swift" \
    "$SCRIPT_DIR/HotKeySmoke.swift" \
    -I "$TEMP_DIR" \
    -L "$TEMP_DIR" \
    -lQuickNotesCore \
    -Xlinker -rpath \
    -Xlinker "$TEMP_DIR" \
    -framework AppKit \
    -framework Carbon \
    -o "$TEMP_DIR/hotkey-smoke"

"$TEMP_DIR/hotkey-smoke"
