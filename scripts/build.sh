#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/.build"
APP="$BUILD/Docktap.app"
DEST="/Applications/Docktap.app"
ICON_SRC="${1:-}"

mkdir -p "$BUILD/icon.iconset" "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling Docktap…"
swiftc -swift-version 5 -O \
  -target arm64-apple-macos13.0 \
  -sdk "$(xcrun --show-sdk-path)" \
  -framework AppKit \
  -framework Carbon \
  -framework ApplicationServices \
  -o "$APP/Contents/MacOS/Docktap" \
  "$ROOT"/Sources/*.swift

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
echo -n "APPL????" > "$APP/Contents/PkgInfo"
cp "$ROOT/Resources/keep-alive.sh" "$APP/Contents/Resources/keep-alive.sh"
chmod +x "$APP/Contents/Resources/keep-alive.sh"

if [[ -z "$ICON_SRC" && -f "$ROOT/Resources/icon.png" ]]; then
  ICON_SRC="$ROOT/Resources/icon.png"
fi

if [[ -n "$ICON_SRC" && -f "$ICON_SRC" ]]; then
  echo "Building icns from $ICON_SRC"
  MASTER="$BUILD/icon-master.png"
  sips -s format png "$ICON_SRC" --out "$MASTER" >/dev/null
  for size in 16 32 64 128 256 512 1024; do
    sips -z $size $size "$MASTER" --out "$BUILD/icon.iconset/icon_${size}x${size}.png" >/dev/null
  done
  sips -z 32 32 "$MASTER" --out "$BUILD/icon.iconset/icon_16x16@2x.png" >/dev/null
  sips -z 64 64 "$MASTER" --out "$BUILD/icon.iconset/icon_32x32@2x.png" >/dev/null
  sips -z 256 256 "$MASTER" --out "$BUILD/icon.iconset/icon_128x128@2x.png" >/dev/null
  sips -z 512 512 "$MASTER" --out "$BUILD/icon.iconset/icon_256x256@2x.png" >/dev/null
  sips -z 1024 1024 "$MASTER" --out "$BUILD/icon.iconset/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$BUILD/icon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
  cp "$APP/Contents/Resources/AppIcon.icns" "$ROOT/Resources/AppIcon.icns"
fi

if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

chmod +x "$ROOT/scripts/codesign-app.sh"
"$ROOT/scripts/codesign-app.sh" "$APP"

uid="$(id -u)"
agent="$HOME/Library/LaunchAgents/com.astucore.docktap.plist"
launchctl bootout "gui/$uid/com.astucore.docktap" 2>/dev/null || true
if pgrep -x Docktap >/dev/null; then
  killall Docktap 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x Docktap >/dev/null || break
    sleep 0.1
  done
  killall -9 Docktap 2>/dev/null || true
fi
rm -rf "$DEST"
cp -R "$APP" "$DEST"
chmod +x "$DEST/Contents/Resources/keep-alive.sh" 2>/dev/null || true
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
NOTARIZE=1 "$ROOT/scripts/codesign-app.sh" "$DEST"

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" >/dev/null 2>&1 || true

cat > "$agent" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>AssociatedBundleIdentifiers</key>
  <array><string>com.astucore.docktap</string></array>
  <key>KeepAlive</key><true/>
  <key>Label</key><string>com.astucore.docktap</string>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
  <key>ProcessType</key><string>Interactive</string>
  <key>ProgramArguments</key>
  <array>
    <string>$DEST/Contents/Resources/keep-alive.sh</string>
    <string>Docktap</string>
    <string>$DEST/Contents/MacOS/Docktap</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/Docktap.err.log</string>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/Docktap.log</string>
  <key>ThrottleInterval</key><integer>3</integer>
</dict>
</plist>
EOF
launchctl enable "gui/$uid/com.astucore.docktap" 2>/dev/null || true
launchctl bootstrap "gui/$uid" "$agent"

echo "Installed $DEST"
ls -la "$DEST/Contents/MacOS/Docktap"
