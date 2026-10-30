#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
VERSION=$(tr -d '\n' < VERSION)
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo 'Invalid VERSION' >&2; exit 1; fi
# -Osize and full LTO retain safe Swift semantics and runtime reflection.
# Keep the combined LTO object so dsymutil can produce usable crash symbols.
# The unstripped executable, object and dSYM stay inside .build.
# Explicit native engine avoids Swift 6.4 swiftbuild recording the deployment
# target as the SDK version in LC_BUILD_VERSION with Command Line Tools.
swift build -c release -Xswiftc -Osize --experimental-lto-mode full \
    -Xlinker -object_path_lto -Xlinker "$PWD/.build/native-release/Taskglass-lto.o" \
    --build-system native --scratch-path .build/native-release --cache-path .build/cache --config-path .build/config --security-path .build/security --manifest-cache local
APP="$PWD/dist/Taskglass.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [ ! -f .build/Taskglass.icns ] || [ scripts/Icon.swift -nt .build/Taskglass.icns ] || [ Assets/Branding/taskglass-logo.png -nt .build/Taskglass.icns ]; then
    mkdir -p .build/Taskglass.iconset
    xcrun swift -module-cache-path .build/module-cache scripts/Icon.swift .build/Taskglass.iconset
    iconutil -c icns .build/Taskglass.iconset -o .build/Taskglass.icns
fi
cp .build/Taskglass.icns "$APP/Contents/Resources/Taskglass.icns"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp .build/native-release/release/Taskglass "$APP/Contents/MacOS/Taskglass.new"
xcrun strip -x -S "$APP/Contents/MacOS/Taskglass.new"
mv -f "$APP/Contents/MacOS/Taskglass.new" "$APP/Contents/MacOS/Taskglass"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Taskglass</string>
<key>CFBundleIdentifier</key><string>dev.taskglass.app</string>
<key>CFBundleIconFile</key><string>Taskglass.icns</string>
<key>CFBundleName</key><string>Taskglass</string>
<key>CFBundleDisplayName</key><string>Taskglass</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSArchitecturePriority</key><array><string>arm64</string></array>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Copyright 2026 Kushagra Bharti and contributors. MIT license.</string>
</dict></plist>
PLIST
# Ad-hoc signing checks bundle integrity. It is not Developer ID signing or notarization.
codesign --force --sign - --options runtime --timestamp=none "$APP"
codesign --verify --strict "$APP"
printf 'Built %s (unsigned preview, ad-hoc integrity signature)\n' "$APP"
