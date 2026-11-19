#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

configuration="${1:-release}"
swift build -c "$configuration"
binary="$(swift build -c "$configuration" --show-bin-path)/AltoTranscription"
app="$PWD/dist/Alto Transcription.app"
mkdir -p "$app/Contents/MacOS"
cp "$binary" "$app/Contents/MacOS/AltoTranscription"
cp Scripts/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
printf '%s\n' "$app"
