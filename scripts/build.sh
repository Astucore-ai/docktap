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

chmod +x "$ROOT/scripts/ensure-identity.sh"
KEYCHAIN="$("$ROOT/scripts/ensure-identity.sh")"
security unlock-keychain -p "docktap-local-sign" "$KEYCHAIN"

# Prefer a trusted local identity. A brand-new Docktap cert is not codesign-valid
# until macOS has been told to trust it (admin dialog). Snaplane's already-trusted
# identity on this machine is a stable fallback; ad-hoc is last resort.
SNAPLANE_KEYCHAIN="/Users/mac/Snaplane/signing/snaplane.keychain-db"
SIGN_NAME="Docktap"
SIGN_KEYCHAIN="$KEYCHAIN"
if ! security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "Docktap"; then
  if [[ -f "$SNAPLANE_KEYCHAIN" ]] && security unlock-keychain -p "snaplane-local-sign" "$SNAPLANE_KEYCHAIN" >/dev/null 2>&1 \
      && security find-identity -v -p codesigning "$SNAPLANE_KEYCHAIN" 2>/dev/null | grep -q "Snaplane"; then
    SIGN_NAME="Snaplane"
    SIGN_KEYCHAIN="$SNAPLANE_KEYCHAIN"
    echo "Signing with existing Snaplane identity (Docktap cert is not yet trusted)"
  else
    SIGN_NAME="-"
    SIGN_KEYCHAIN=""
    echo "Signing ad-hoc (no trusted local identity)"
  fi
fi

OLD_KEYCHAINS=("${(@f)$(security list-keychains -d user | sed 's/^ *"//; s/"$//')}")
if [[ -n "$SIGN_KEYCHAIN" ]]; then
  security list-keychains -d user -s "$SIGN_KEYCHAIN" "$KEYCHAIN" "${OLD_KEYCHAINS[@]}"
else
  security list-keychains -d user -s "$KEYCHAIN" "${OLD_KEYCHAINS[@]}"
fi
cleanup_keychains() {
  security list-keychains -d user -s "${OLD_KEYCHAINS[@]}" >/dev/null || true
}
trap cleanup_keychains EXIT

sign_app() {
  if [[ "$SIGN_NAME" == "-" ]]; then
    codesign --force --sign - --identifier com.astucore.docktap "$1"
  else
    codesign --force --sign "$SIGN_NAME" --keychain "$SIGN_KEYCHAIN" \
      --identifier com.astucore.docktap \
      "$1"
  fi
}

sign_app "$APP"

if pgrep -x Docktap >/dev/null; then
  killall Docktap 2>/dev/null || true
  sleep 0.3
fi
rm -rf "$DEST"
cp -R "$APP" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
sign_app "$DEST"

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" >/dev/null 2>&1 || true

echo "Installed $DEST"
ls -la "$DEST/Contents/MacOS/Docktap"
