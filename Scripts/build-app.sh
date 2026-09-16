#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
CACHE_ROOT="/private/tmp/window-crt-lens-build"
APP="$CACHE_ROOT/output/Window CRT Lens.app"
ARCHIVE="$ROOT/dist/Window CRT Lens.app.zip"

mkdir -p "$CACHE_ROOT/clang" "$CACHE_ROOT/swiftpm" "$CACHE_ROOT/cache" "$CACHE_ROOT/config" "$CACHE_ROOT/security"

CLANG_MODULE_CACHE_PATH="$CACHE_ROOT/clang" \
SWIFTPM_MODULECACHE_OVERRIDE="$CACHE_ROOT/swiftpm" \
swift build \
    --package-path "$ROOT" \
    --disable-sandbox \
    --cache-path "$CACHE_ROOT/cache" \
    --config-path "$CACHE_ROOT/config" \
    --security-path "$CACHE_ROOT/security" \
    -c release \
    --product WindowCRTLens

BIN_PATH=$(CLANG_MODULE_CACHE_PATH="$CACHE_ROOT/clang" SWIFTPM_MODULECACHE_OVERRIDE="$CACHE_ROOT/swiftpm" swift build --package-path "$ROOT" --disable-sandbox --cache-path "$CACHE_ROOT/cache" --config-path "$CACHE_ROOT/config" --security-path "$CACHE_ROOT/security" -c release --show-bin-path)

rm -rf "$CACHE_ROOT/output"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/WindowCRTLens" "$APP/Contents/MacOS/WindowCRTLens"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE.txt"
xattr -cr "$APP"
codesign \
    --force \
    --sign - \
    --identifier com.rey.window-crt-lens.test \
    --requirements '=designated => identifier "com.rey.window-crt-lens.test"' \
    "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

mkdir -p "$ROOT/dist"
rm -rf "$ROOT/dist/Window CRT Lens.app"
rm -f "$ARCHIVE"
ditto -c -k --keepParent --sequesterRsrc "$APP" "$ARCHIVE"

echo "$ARCHIVE"
