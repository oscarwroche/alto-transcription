#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

configuration="${1:-release}"
swift build -c "$configuration"
bin_path="$(swift build -c "$configuration" --show-bin-path)"
app_name=$(plutil -extract CFBundleName raw Scripts/Info.plist)
app="$PWD/dist/$app_name.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks"
cp "$bin_path/AltoTranscription" "$app/Contents/MacOS/AltoTranscription"
cp Scripts/Info.plist "$app/Contents/Info.plist"
ditto "$bin_path/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
printf '%s\n' "$app"
