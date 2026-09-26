#!/bin/bash
# Package a built Shadow.app and shadow CLI into release artifacts.
#
# Environment:
#   VERSION      release version used in artifact names (default: VERSION file)
#   OUT_DIR      directory that contains Shadow.app and shadow and receives the
#                artifacts (default: dist)
#   ALLOW_THIN   set to 1 to package single-architecture binaries (local testing);
#                by default both must contain arm64 and x86_64
#
# Produces, in OUT_DIR:
#   Shadow-$VERSION-macos-universal.zip
#   Shadow-$VERSION-macos-universal.dmg
#   shadow-$VERSION-macos-universal.tar.gz   (the CLI, LICENSE and README.md)
#   SHA256SUMS.txt
set -euo pipefail

cd "$(dirname "$0")"

VERSION="${VERSION:-$(tr -d '[:space:]' < VERSION)}"
OUT_DIR="${OUT_DIR:-dist}"
APP_PATH="$OUT_DIR/Shadow.app"
CLI_PATH="$OUT_DIR/shadow"
BASE_NAME="Shadow-$VERSION-macos-universal"
ZIP_NAME="$BASE_NAME.zip"
DMG_NAME="$BASE_NAME.dmg"
TAR_NAME="shadow-$VERSION-macos-universal.tar.gz"

if [ -z "$VERSION" ]; then
    echo "error: VERSION is empty" >&2
    exit 1
fi

if [ ! -d "$APP_PATH" ] || [ ! -f "$CLI_PATH" ]; then
    echo "error: '$APP_PATH' or '$CLI_PATH' not found. Run ./build.sh first." >&2
    exit 1
fi

check_archs() {
    local binary="$1"
    local found
    found="$(lipo -archs "$binary")"
    echo "$binary: $found"
    for arch in arm64 x86_64; do
        case " $found " in
            *" $arch "*) ;;
            *)
                if [ "${ALLOW_THIN:-0}" != "1" ]; then
                    echo "error: $binary lacks $arch; build with ARCHS=\"arm64 x86_64\" or set ALLOW_THIN=1" >&2
                    exit 1
                fi
                echo "warning: $binary lacks $arch (ALLOW_THIN=1)" >&2
                ;;
        esac
    done
}

check_archs "$APP_PATH/Contents/MacOS/Shadow"
check_archs "$CLI_PATH"

codesign --verify --deep --strict "$APP_PATH"
codesign --verify --strict "$CLI_PATH"

rm -f "$OUT_DIR/$ZIP_NAME" "$OUT_DIR/$DMG_NAME" "$OUT_DIR/$TAR_NAME" "$OUT_DIR/SHA256SUMS.txt"

echo "Creating $OUT_DIR/$ZIP_NAME..."
ditto -c -k --keepParent "$APP_PATH" "$OUT_DIR/$ZIP_NAME"

APP_DIR="$OUT_DIR" DMG_NAME="$DMG_NAME" ./dmg.sh

echo "Creating $OUT_DIR/$TAR_NAME..."
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/shadow-cli.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
mkdir -p "$STAGING/shadow-$VERSION"
cp "$CLI_PATH" LICENSE README.md "$STAGING/shadow-$VERSION/"
tar -czf "$OUT_DIR/$TAR_NAME" -C "$STAGING" "shadow-$VERSION"

(
    cd "$OUT_DIR"
    shasum -a 256 "$ZIP_NAME" "$DMG_NAME" "$TAR_NAME" > SHA256SUMS.txt
    echo ""
    echo "SHA256SUMS.txt:"
    /bin/cat SHA256SUMS.txt
)
