#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(tr -d '\n' < VERSION)
APP="$PWD/dist/Taskglass.app"
[[ -d "$APP" ]] || { echo 'Run scripts/build-app.sh first' >&2; exit 1; }
BUNDLE_VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
[[ "$VERSION" == "$BUNDLE_VERSION" ]] || { echo 'Build version differs from VERSION' >&2; exit 1; }
codesign --verify --strict "$APP"
OUT="$PWD/dist/release"
STAGE="$PWD/.build/release-stage"
mkdir -p "$OUT"
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Taskglass.app"
ln -s /Applications "$STAGE/Applications"
cp docs/INSTALL.txt "$STAGE/READ ME FIRST.txt"
NAME="Taskglass-$VERSION-arm64-unsigned"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/$NAME.zip"
hdiutil create -volname "Taskglass $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$OUT/$NAME.dmg"
(cd "$OUT" && shasum -a 256 "$NAME.dmg" "$NAME.zip" > SHA256SUMS.txt)
printf 'Packaged %s\n' "$OUT"
