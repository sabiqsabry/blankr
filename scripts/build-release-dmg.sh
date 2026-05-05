#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/Blankr.xcodeproj"
SCHEME="Blankr"
CONFIG="Release"
DERIVED="$ROOT/.build/DerivedData"
DIST="$ROOT/dist"
APP="$DERIVED/Build/Products/$CONFIG/Blankr.app"

rm -rf "$DERIVED/Build/Products/$CONFIG/Blankr.app" 2>/dev/null || true
mkdir -p "$DIST"

echo "Building $SCHEME ($CONFIG)..."
/usr/bin/xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  -destination "platform=macOS" \
  build

if [[ ! -d "$APP" ]]; then
  echo "error: expected app at $APP"
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo "0.0.0")"
STAGE="$(mktemp -d)"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

echo "Staging disk image contents..."
/usr/bin/ditto "$APP" "$STAGE/Blankr.app"
/bin/ln -sf /Applications "$STAGE/Applications"

DMG="$DIST/Blankr-${VERSION}-macOS.dmg"
rm -f "$DMG"

echo "Creating ${DMG}..."
/usr/bin/hdiutil create \
  -volname "Blankr." \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG"

echo "Done: $DMG"
/bin/ls -lh "$DMG"
