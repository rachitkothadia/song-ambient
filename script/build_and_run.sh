#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
APP_NAME=SongAmbient
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
BUILD_CONFIGURATION=release
if [[ "$MODE" == --debug ]]; then BUILD_CONFIGURATION=debug; fi
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
swift build -c "$BUILD_CONFIGURATION"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path)/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Assets/SongAmbient.icns "$APP_BUNDLE/Contents/Resources/SongAmbient.icns"
cp LICENSE "$APP_BUNDLE/Contents/Resources/LICENSE.txt"
cp -f .build/checkouts/Yams/LICENSE "$APP_BUNDLE/Contents/Resources/Yams-LICENSE.txt"
cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SongAmbient</string>
<key>CFBundleIdentifier</key><string>local.rachit.songambient</string>
<key>CFBundleName</key><string>Song Ambient</string>
<key>CFBundleDisplayName</key><string>Song Ambient</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>2.1.1</string>
<key>CFBundleVersion</key><string>4</string>
<key>CFBundleIconFile</key><string>SongAmbient</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSAppleEventsUsageDescription</key><string>Song Ambient reads track information and controls playback in your selected player, Spotify or Music.</string>
<key>NSAudioCaptureUsageDescription</key><string>Song Ambient analyzes the output of your selected audio source to animate the border. The microphone is never used. Audio is processed locally and never saved.</string>
</dict></plist>
PLIST
/usr/bin/codesign --force --sign - --entitlements "$ROOT_DIR/script/SongAmbient.entitlements" "$APP_BUNDLE"
case "$MODE" in
  --build) ;;
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
  --verify) /usr/bin/open -n "$APP_BUNDLE"; sleep 1; pgrep -x "$APP_NAME" >/dev/null; echo 'Build and launch verified.' ;;
  --ui-check) /usr/bin/open -n "$APP_BUNDLE" --args --no-overlay --test-ui; sleep 1; pgrep -x "$APP_NAME" >/dev/null ;;
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
  --logs) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'process == "SongAmbient"' ;;
  --telemetry) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'subsystem == "local.rachit.songambient"' ;;
  *) echo "Usage: $0 [run|--build|--verify|--ui-check|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac
