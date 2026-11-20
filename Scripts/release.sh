#!/bin/bash
set -euo pipefail

if [[ $# != 3 ]]; then
  echo "Usage: $0 /path/to/Wavelength.app 1.0 1" >&2
  exit 1
fi

APP_PATH="$1"
SHORT_VERSION="$2"
BUILD_VERSION="$3"
APP_NAME=$(basename "$APP_PATH" .app)
ZIP_NAME="${APP_NAME}_${SHORT_VERSION}.zip"

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SPARKLE_BIN="${SPARKLE_BIN:-$SCRIPT_DIR/../build/SourcePackages/artifacts/sparkle/Sparkle/bin}"
ACCOUNT="blog.micro.wavelength"
PLIST="$APP_PATH/Contents/Info.plist"

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST"
}

if [[ ! -x "$SPARKLE_BIN/sign_update" || ! -x "$SPARKLE_BIN/generate_keys" ]]; then
  echo "Set SPARKLE_BIN to the bin directory from the resolved Sparkle package." >&2
  exit 1
fi

if [[ "$SHORT_VERSION" != "$(plist_value CFBundleShortVersionString)" ||
      "$BUILD_VERSION" != "$(plist_value CFBundleVersion)" ]]; then
  echo "Version and build must match the exported app." >&2
  exit 1
fi

FEED_URL=$(plist_value SUFeedURL)
APP_KEY=$(plist_value SUPublicEDKey)
if [[ "$FEED_URL" != https://*/*.xml || -z "$APP_KEY" ]]; then
  echo "Build the app with an HTTPS appcast URL and a Sparkle public key." >&2
  exit 1
fi

if [[ "$APP_KEY" != "$("$SPARKLE_BIN/generate_keys" --account "$ACCOUNT" -p)" ]]; then
  echo "The app's public key does not match the Wavelength signing key in Keychain." >&2
  exit 1
fi

echo "creating archive..."
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_NAME"

echo "signing update..."
SIGNATURE=$("$SPARKLE_BIN/sign_update" --account "$ACCOUNT" -p "$ZIP_NAME")
LENGTH=$(stat -f%z "$ZIP_NAME")

printf '\nUpload this file:\n%s\n\nAppcast enclosure:\n\n' "$ZIP_NAME"
cat <<EOF
<enclosure url="${FEED_URL%/*}/$ZIP_NAME"
           sparkle:shortVersionString="$SHORT_VERSION"
           sparkle:version="$BUILD_VERSION"
           sparkle:edSignature="$SIGNATURE"
           length="$LENGTH"
           type="application/octet-stream" />
EOF
