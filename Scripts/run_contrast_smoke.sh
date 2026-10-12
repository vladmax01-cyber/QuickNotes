#!/bin/bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/quick-notes-contrast.XXXXXX")"
trap 'rm -rf -- "$TEMP_DIR"' EXIT

swiftc \
    "$SCRIPT_DIR/ContrastSmoke.swift" \
    -parse-as-library \
    -framework AppKit \
    -o "$TEMP_DIR/contrast-smoke"

"$TEMP_DIR/contrast-smoke"
