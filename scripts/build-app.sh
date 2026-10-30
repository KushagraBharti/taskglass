#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift build -c release --scratch-path .build --cache-path .build/cache --config-path .build/config --security-path .build/security --manifest-cache local
APP="$PWD/dist/Taskglass.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [ ! -f .build/Taskglass.icns ] || [ scripts/Icon.swift -nt .build/Taskglass.icns ]; then
    mkdir -p .build/Taskglass.iconset
    xcrun swift -module-cache-path .build/module-cache scripts/Icon.swift .build/Taskglass.iconset
    iconutil -c icns .build/Taskglass.iconset -o .build/Taskglass.icns
fi
cp .build/Taskglass.icns "$APP/Contents/Resources/Taskglass.icns"
cp .build/release/Taskglass "$APP/Contents/MacOS/Taskglass.new"
mv -f "$APP/Contents/MacOS/Taskglass.new" "$APP/Contents/MacOS/Taskglass"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Taskglass</string>
<key>CFBundleIdentifier</key><string>dev.taskglass.app</string>
<key>CFBundleIconFile</key><string>Taskglass</string>
<key>CFBundleName</key><string>Taskglass</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
printf 'Built %s\n' "$APP"
