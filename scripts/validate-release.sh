#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/dist/Taskglass.app"
VERSION=$(tr -d '\n' < VERSION)
NAME="Taskglass-$VERSION-arm64-unsigned"
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist")" == dev.taskglass.app ]]
BUILD_INFO=$(xcrun vtool -show-build "$APP/Contents/MacOS/Taskglass")
[[ "$(awk '$1 == "minos" {print $2}' <<< "$BUILD_INFO")" == 14.0 ]]
SDK_VERSION=$(awk '$1 == "sdk" {print $2}' <<< "$BUILD_INFO")
[[ "${SDK_VERSION%%.*}" -ge 26 ]]
[[ "$(lipo -archs "$APP/Contents/MacOS/Taskglass")" == arm64 ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' "$APP/Contents/Info.plist")" == 14.0 ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")" == "$VERSION" ]]
[[ -s "$APP/Contents/Resources/Taskglass.icns" ]]
[[ -s "$APP/Contents/Resources/LICENSE.txt" ]]
[[ -s "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md" ]]
codesign --verify --strict "$APP"
codesign -dvv "$APP" 2>&1 | sed -n '/Signature=/p; /TeamIdentifier=/p; /Runtime Version=/p'
(cd dist/release && shasum -a 256 -c SHA256SUMS.txt)
hdiutil verify "dist/release/$NAME.dmg"
CHECK="$PWD/.build/release-validation"
rm -rf "$CHECK"
mkdir -p "$CHECK/zip" "$CHECK/mount"
ditto -x -k "dist/release/$NAME.zip" "$CHECK/zip"
codesign --verify --strict "$CHECK/zip/Taskglass.app"
cmp "$APP/Contents/MacOS/Taskglass" "$CHECK/zip/Taskglass.app/Contents/MacOS/Taskglass"
hdiutil attach -readonly -nobrowse -mountpoint "$CHECK/mount" "dist/release/$NAME.dmg"
trap 'hdiutil detach "$CHECK/mount" >/dev/null' EXIT
codesign --verify --strict "$CHECK/mount/Taskglass.app"
[[ "$(readlink "$CHECK/mount/Applications")" == /Applications ]]
cmp "$APP/Contents/MacOS/Taskglass" "$CHECK/mount/Taskglass.app/Contents/MacOS/Taskglass"
printf 'Release validation PASS\n'
