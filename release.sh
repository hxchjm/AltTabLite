#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="AltTabLite"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
DIST_DIR="dist"
STAGE_DIR="$DIST_DIR/stage"
ARCHIVE="$DIST_DIR/$APP_NAME-$VERSION.zip"

rm -rf "$STAGE_DIR" "$ARCHIVE" "$ARCHIVE.sha256"
mkdir -p "$STAGE_DIR"

BUILD_DIR="$STAGE_DIR" CODE_SIGN_IDENTITY="-" ./build.sh

echo "Verifying signature..."
codesign --verify --strict --verbose=2 "$STAGE_DIR/$APP_NAME.app"
codesign -dv "$STAGE_DIR/$APP_NAME.app" 2>&1 | grep -E "Identifier|Signature"

ditto -c -k --keepParent "$STAGE_DIR/$APP_NAME.app" "$ARCHIVE"
(cd "$DIST_DIR" && shasum -a 256 "$(basename "$ARCHIVE")" > "$(basename "$ARCHIVE").sha256")
rm -rf "$STAGE_DIR"

echo "Archive:  $ARCHIVE"
echo "SHA-256:  $(cat "$ARCHIVE.sha256")"
