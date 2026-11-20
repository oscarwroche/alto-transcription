#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

output_dir="${1:-dist}"
app_name=$(plutil -extract CFBundleName raw Scripts/Info.plist)
source_app="${ALTO_DIST_DIR:-dist}/$app_name.app"
version=$(plutil -extract CFBundleShortVersionString raw "$source_app/Contents/Info.plist")
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Expected a three-part app version in the built bundle." >&2
  exit 1
fi

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
app="$stage/$app_name.app"
ditto "$source_app" "$app"
codesign --verify --deep --strict "$app"
ln -s /Applications "$stage/Applications"

mkdir -p "$output_dir"
dmg_name="${app_name// /-}-v$version-macOS-$(uname -m).dmg"
hdiutil create -ov -format UDZO -volname "$app_name $version" -srcfolder "$stage" "$output_dir/$dmg_name"
hdiutil verify "$output_dir/$dmg_name"
(
  cd "$output_dir"
  shasum -a 256 "$dmg_name" > "$dmg_name.sha256"
)
