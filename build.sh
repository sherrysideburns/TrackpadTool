#!/bin/bash
# Builds TrackpadTool.app into ./build
# Usage: ./build.sh          build only
#        ./build.sh --run    build, then (re)start the app
set -euo pipefail
cd "$(dirname "$0")"

if ! xcrun --find swift >/dev/null 2>&1; then
    echo "Apple's Command Line Tools are needed. Run:  xcode-select --install"
    exit 1
fi

echo "Building…"
swift build -c release 2>&1 | tee build-log.txt
BIN="$(swift build -c release --show-bin-path)/TrackpadTool"

APP="build/TrackpadTool.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TrackpadTool"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/MenuBarIcon.png Resources/MenuBarIcon@2x.png "$APP/Contents/Resources/"
touch "$APP"   # so the Dock picks up the new icon

# Sign with a stable identity if you made one (keeps Accessibility permission
# across rebuilds); otherwise sign ad-hoc.
IDENTITY="TrackpadTool Dev"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    codesign --force --sign "$IDENTITY" --identifier com.sherrysideburns.TrackpadTool "$APP"
else
    codesign --force --sign - --identifier com.sherrysideburns.TrackpadTool "$APP"
fi

echo "Built $APP"

if [ "${1:-}" = "--run" ]; then
    pkill -x TrackpadTool 2>/dev/null || true
    sleep 0.5
    open "$APP"
fi
