#!/bin/bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly APP_NAME="Quick Notes"
readonly DMG_NAME="$APP_NAME.dmg"
readonly EXECUTABLE_NAME="QuickNotes"
readonly INFO_PLIST_SOURCE="$PROJECT_DIR/Resources/Info.plist"
readonly ICON_SOURCE="$PROJECT_DIR/Resources/QuickNotes.icns"

if (( $# > 1 )); then
    echo "Usage: $0 [output-directory]" >&2
    exit 64
fi

OUTPUT_ARGUMENT="${1:-$PROJECT_DIR/../../outputs}"
mkdir -p "$OUTPUT_ARGUMENT"
readonly OUTPUT_DIR="$(cd "$OUTPUT_ARGUMENT" && pwd -P)"

if [[ "$OUTPUT_DIR" == "/" ]]; then
    echo "Refusing to use the filesystem root as the output directory." >&2
    exit 64
fi

for required_tool in swift plutil codesign lipo install mktemp xattr hdiutil; do
    if ! command -v "$required_tool" >/dev/null 2>&1; then
        echo "Required tool not found: $required_tool" >&2
        exit 69
    fi
done

if [[ ! -f "$INFO_PLIST_SOURCE" ]]; then
    echo "Info.plist not found: $INFO_PLIST_SOURCE" >&2
    exit 66
fi
if [[ ! -f "$ICON_SOURCE" ]]; then
    echo "App icon not found: $ICON_SOURCE" >&2
    exit 66
fi

echo "Building $EXECUTABLE_NAME for arm64 (release)..."
swift build \
    --package-path "$PROJECT_DIR" \
    --configuration release \
    --arch arm64

readonly BIN_DIRECTORY="$(
    swift build \
        --package-path "$PROJECT_DIR" \
        --configuration release \
        --arch arm64 \
        --show-bin-path
)"
readonly BUILT_EXECUTABLE="$BIN_DIRECTORY/$EXECUTABLE_NAME"

if [[ ! -f "$BUILT_EXECUTABLE" ]]; then
    echo "Release executable not found: $BUILT_EXECUTABLE" >&2
    exit 66
fi

STAGING_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/quick-notes-package.XXXXXX")"
readonly STAGING_DIRECTORY

cleanup() {
    if [[ -n "${STAGING_DIRECTORY:-}" && -d "$STAGING_DIRECTORY" ]]; then
        rm -rf -- "$STAGING_DIRECTORY"
    fi
}
trap cleanup EXIT

readonly PACKAGE_ROOT="$STAGING_DIRECTORY/package"
readonly STAGED_APP="$PACKAGE_ROOT/$APP_NAME.app"
readonly STAGED_CONTENTS="$STAGED_APP/Contents"
readonly STAGED_EXECUTABLE="$STAGED_CONTENTS/MacOS/$EXECUTABLE_NAME"
readonly STAGED_INFO_PLIST="$STAGED_CONTENTS/Info.plist"
readonly STAGED_DMG="$STAGING_DIRECTORY/$DMG_NAME"

mkdir -p "$STAGED_CONTENTS/MacOS" "$STAGED_CONTENTS/Resources"
install -m 0755 "$BUILT_EXECUTABLE" "$STAGED_EXECUTABLE"
install -m 0644 "$INFO_PLIST_SOURCE" "$STAGED_INFO_PLIST"
install -m 0644 "$ICON_SOURCE" "$STAGED_CONTENTS/Resources/QuickNotes.icns"
chmod 0755 "$STAGED_APP" "$STAGED_CONTENTS" "$STAGED_CONTENTS/MacOS" "$STAGED_CONTENTS/Resources"
xattr -cr "$STAGED_APP"

echo "Signing app bundle with an ad-hoc signature..."
codesign \
    --force \
    --deep \
    --sign - \
    --timestamp=none \
    "$STAGED_APP"

validate_app() {
    local app_path="$1"
    local plist_path="$app_path/Contents/Info.plist"
    local executable_path="$app_path/Contents/MacOS/$EXECUTABLE_NAME"
    local plist_executable
    local plist_package_type
    local architectures

    plutil -lint "$plist_path" >/dev/null

    plist_executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist_path")"
    if [[ "$plist_executable" != "$EXECUTABLE_NAME" ]]; then
        echo "CFBundleExecutable is '$plist_executable'; expected '$EXECUTABLE_NAME'." >&2
        return 1
    fi

    plist_package_type="$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$plist_path")"
    if [[ "$plist_package_type" != "APPL" ]]; then
        echo "CFBundlePackageType is '$plist_package_type'; expected 'APPL'." >&2
        return 1
    fi

    if [[ ! -x "$executable_path" ]]; then
        echo "Bundled executable is missing or is not executable: $executable_path" >&2
        return 1
    fi

    architectures="$(lipo -archs "$executable_path")"
    if [[ " $architectures " != *" arm64 "* ]]; then
        echo "Bundled executable does not contain arm64 code (found: $architectures)." >&2
        return 1
    fi

    codesign --verify --deep --strict --verbose=2 "$app_path"
}

echo "Validating staged bundle..."
validate_app "$STAGED_APP"

ln -s /Applications "$PACKAGE_ROOT/Applications"
echo "Creating disk image..."
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$PACKAGE_ROOT" \
    -format UDZO \
    -ov \
    "$STAGED_DMG" >/dev/null
hdiutil verify "$STAGED_DMG" >/dev/null

readonly FINAL_DMG="$OUTPUT_DIR/$DMG_NAME"
install -m 0644 "$STAGED_DMG" "$FINAL_DMG"
hdiutil verify "$FINAL_DMG" >/dev/null

# File Provider folders may add Finder metadata that invalidates strict signatures.
# The disk image preserves the verified bundle exactly as signed.
readonly FINAL_APP="$OUTPUT_DIR/$APP_NAME.app"
if [[ -e "$FINAL_APP" ]]; then
    rm -rf -- "$FINAL_APP"
fi

echo "Built and validated: $FINAL_DMG"
