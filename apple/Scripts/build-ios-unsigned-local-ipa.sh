#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APPLE_DIR="$ROOT_DIR/apple"
SCHEME="Slipstream"
CONFIGURATION="${CONFIGURATION:-Release}"
BUILD_DIR="${BUILD_DIR:-$APPLE_DIR/.build/ios-unsigned-local}"
PAYLOAD_DIR="$BUILD_DIR/Payload"
IPA_PATH="$BUILD_DIR/Slipstream-unsigned.ipa"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

if ! xcodebuild -version >/dev/null 2>&1; then
  cat <<'MSG' >&2
Xcode is required for iOS IPA builds.

Run once in Terminal:
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  sudo xcodebuild -license accept

Then rerun:
  ./apple/Scripts/build-ios-unsigned-local-ipa.sh
MSG
  exit 1
fi

if ! command -v gomobile >/dev/null 2>&1; then
  echo "gomobile not found. Install with:" >&2
  echo "  go install golang.org/x/mobile/cmd/gomobile@latest" >&2
  echo "  gomobile init" >&2
  exit 1
fi

gomobile init >/dev/null 2>&1 || true
"$APPLE_DIR/Scripts/build-xcframework.sh"

if command -v xcodegen >/dev/null 2>&1; then
  (cd "$APPLE_DIR" && xcodegen generate)
else
  echo "xcodegen not found; assuming Slipstream.xcodeproj is already generated." >&2
fi

rm -rf "$BUILD_DIR"
mkdir -p "$PAYLOAD_DIR"

xcodebuild \
  -project "$APPLE_DIR/Slipstream.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -sdk iphoneos \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP_PATH="$(find "$BUILD_DIR/DerivedData/Build/Products/$CONFIGURATION-iphoneos" -maxdepth 1 -name '*.app' -print -quit)"
if [[ -z "$APP_PATH" ]]; then
  echo "Build finished, but no .app was found." >&2
  exit 1
fi

cp -R "$APP_PATH" "$PAYLOAD_DIR/"
APP_BUNDLE="$PAYLOAD_DIR/$(basename "$APP_PATH")"

# The Mobile.framework directory is left behind by Xcode's binaryTarget
# embedder, but every gomobile symbol is already statically linked into the
# main app binary (verified via `nm` / `otool -L`). The framework binary is a
# 33 KB ar archive that iOS never dlopens (no LC_LOAD_DYLIB references it),
# so we drop it to keep the IPA lean and avoid future codesign surprises.
rm -rf "$APP_BUNDLE/Frameworks"

rm -f "$IPA_PATH"
(cd "$BUILD_DIR" && /usr/bin/zip -qry "$IPA_PATH" Payload)

echo
echo "Built unsigned IPA:"
echo "  $IPA_PATH"
echo
echo "Next steps:"
echo "  1) Open Sideloadly (or AltStore) and drop the .ipa in."
echo "  2) Sign with your Apple ID and install onto the iPhone."
echo "  3) Trust the developer profile in Settings → General → VPN & Device Management."
