#!/bin/bash
# Build Shadow.app and the shadow CLI from source and ad-hoc sign both.
#
# Environment:
#   VERSION        marketing version written to the bundle
#                  (default: exact git tag on HEAD without the v, else the VERSION file)
#   BUILD_NUMBER   CFBundleVersion (default: git commit count, then 1)
#   ARCHS          space-separated architectures, e.g. "arm64 x86_64"
#                  (default: the current machine)
#   OUT_DIR        output directory; the app is assembled at $OUT_DIR/Shadow.app
#                  and the CLI is written to $OUT_DIR/shadow (default: dist)
#   SWIFT_FLAGS    extra flags for swift build, e.g. --disable-sandbox
#   SIGN_IDENTITY  codesign identity (default: "-" for ad-hoc)
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Shadow"
APP_PRODUCT="ShadowApp"
CLI_NAME="shadow"

# Prefer an exact tag on HEAD (release builds), otherwise the VERSION file.
if [ -z "${VERSION:-}" ]; then
    VERSION="$(git describe --tags --exact-match 2>/dev/null | sed 's/^v//' || true)"
fi
if [ -z "${VERSION:-}" ] && [ -f VERSION ]; then
    VERSION="$(tr -d '[:space:]' < VERSION)"
fi
if [ -z "${VERSION:-}" ]; then
    echo "error: VERSION could not be determined" >&2
    exit 1
fi
if [ -z "${BUILD_NUMBER:-}" ]; then
    BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
fi
ARCHS="${ARCHS:-$(uname -m)}"
OUT_DIR="${OUT_DIR:-dist}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP_BUNDLE="$OUT_DIR/$APP_NAME.app"
CLI_PATH="$OUT_DIR/$CLI_NAME"

# shellcheck disable=SC2206
SWIFT_EXTRA=(${SWIFT_FLAGS:-})

echo "Building $APP_NAME $VERSION ($BUILD_NUMBER) for: $ARCHS"

APP_BINARIES=()
CLI_BINARIES=()
for arch in $ARCHS; do
    triple="$arch-apple-macosx"
    echo "swift build -c release --triple $triple ${SWIFT_EXTRA[*]:-}"
    swift build -c release --triple "$triple" ${SWIFT_EXTRA[@]+"${SWIFT_EXTRA[@]}"}
    bin_dir="$(swift build -c release --triple "$triple" ${SWIFT_EXTRA[@]+"${SWIFT_EXTRA[@]}"} --show-bin-path)"
    APP_BINARIES+=("$bin_dir/$APP_PRODUCT")
    CLI_BINARIES+=("$bin_dir/$CLI_NAME")
done

echo "Assembling $APP_BUNDLE..."
mkdir -p "$OUT_DIR"
rm -rf "$APP_BUNDLE" "$CLI_PATH"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

if [ "${#APP_BINARIES[@]}" -gt 1 ]; then
    lipo -create "${APP_BINARIES[@]}" -output "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    lipo -create "${CLI_BINARIES[@]}" -output "$CLI_PATH"
else
    cp "${APP_BINARIES[0]}" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    cp "${CLI_BINARIES[0]}" "$CLI_PATH"
fi

cp Info.plist "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"

if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

echo "Signing with identity: $SIGN_IDENTITY"
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none --identifier com.mk24x7.shadow.cli "$CLI_PATH"
codesign --verify --strict --verbose=2 "$CLI_PATH"

echo ""
echo "Built: $APP_BUNDLE"
echo "Architectures: $(lipo -archs "$APP_BUNDLE/Contents/MacOS/$APP_NAME")"
echo "Size: $(du -sh "$APP_BUNDLE" | cut -f1)"
echo "Built: $CLI_PATH ($(lipo -archs "$CLI_PATH"))"
echo ""
echo "Next: ./package.sh (zip, dmg, CLI tarball, checksums) or APP_DIR=$OUT_DIR ./dmg.sh"
