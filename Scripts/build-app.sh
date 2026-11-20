#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

configuration="${1:-release}"
output_dir="${ALTO_DIST_DIR:-dist}"
identity="${ALTO_SIGN_IDENTITY:-}"
swift build -c "$configuration"
bin_path="$(swift build -c "$configuration" --show-bin-path)"
app_name=$(plutil -extract CFBundleName raw Scripts/Info.plist)
mkdir -p "$output_dir"
app="$(cd "$output_dir" && pwd)/$app_name.app"
framework="$app/Contents/Frameworks/Sparkle.framework"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks" "$app/Contents/Resources/en.lproj"
cp "$bin_path/AltoTranscription" "$app/Contents/MacOS/AltoTranscription"
cp Scripts/Info.plist "$app/Contents/Info.plist"
cp Scripts/InfoPlist.strings "$app/Contents/Resources/en.lproj/InfoPlist.strings"
ditto "$bin_path/Sparkle.framework" "$framework"

if [[ -n "$identity" ]]; then
  sparkle="$framework/Versions/Current"
  signing=(codesign --force --sign "$identity" --timestamp --options runtime)
  "${signing[@]}" "$sparkle/XPCServices/Installer.xpc"
  "${signing[@]}" --preserve-metadata=entitlements "$sparkle/XPCServices/Downloader.xpc"
  "${signing[@]}" "$sparkle/Autoupdate" "$sparkle/Updater.app"
  "${signing[@]}" "$framework"
  "${signing[@]}" "$app"
  codesign --verify -R='anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists' "$app"
else
  codesign --force --sign - "$app"
fi
codesign --verify --deep --strict "$app"
printf '%s\n' "$app"
