#!/bin/bash
# Builds build/SpaceNamer.app. Set SIGN_ID to a codesigning identity to keep
# the Accessibility permission across rebuilds (ad-hoc signing loses it).
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=build/SpaceNamer.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/SpaceNamer "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"

mkdir -p "$APP/Contents/Resources"
cp assets/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign "${SIGN_ID:--}" "$APP"
echo "Built $APP"
