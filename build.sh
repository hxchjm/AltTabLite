#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="AltTabLite"
APP_DIR="${BUILD_DIR:-build}/$APP_NAME.app"
BINARY="$APP_DIR/Contents/MacOS/$APP_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"

echo "Compiling..."
swiftc -O Sources/*.swift -o "$BINARY"

cp Info.plist "$APP_DIR/Contents/Info.plist"

SIGN_ID="${CODE_SIGN_IDENTITY:-AltTabLite Dev}"
echo "Signing with identity: $SIGN_ID"
codesign --force --sign "$SIGN_ID" "$APP_DIR"

echo "Built: $APP_DIR"
echo "Run:   open $APP_DIR"
