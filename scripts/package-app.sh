#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release --product MacWhiteboard
APP="dist/MacWhiteboard.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/MacWhiteboard "$APP/Contents/MacOS/MacWhiteboard"
cp Support/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"
