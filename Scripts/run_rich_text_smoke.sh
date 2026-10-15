#!/bin/bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly OUTPUT="${TMPDIR:-/tmp}/QuickNotesRichTextSmoke"

swiftc \
    "$PROJECT_DIR/Sources/QuickNotes/Views/NoteRichContent.swift" \
    "$PROJECT_DIR/Sources/QuickNotes/Views/RichTextEditorController.swift" \
    "$PROJECT_DIR/Sources/QuickNotes/Views/NativeTextEditor.swift" \
    "$PROJECT_DIR/Scripts/RichTextSmoke.swift" \
    -framework AppKit \
    -o "$OUTPUT"

"$OUTPUT"
