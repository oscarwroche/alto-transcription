#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 'Developer ID Application: Name (TEAMID)' [keychain profile]" >&2
  exit 1
fi
identity=$1
profile="${2:-body-and-soul-notary}"
commit=$(git rev-parse HEAD)
identities=$(security find-identity -v -p codesigning)
if ! grep -qF 'Developer ID Application:' <<< "$identities"; then
  echo "Install a Developer ID Application certificate with its private key in this Mac's Keychain." >&2
  exit 1
fi
if ! git diff --quiet HEAD -- Package.swift Package.resolved Scripts Sources ||
   [[ -n $(git ls-files --others --exclude-standard -- Package.swift Package.resolved Scripts Sources) ]]; then
  echo "Commit build inputs before creating an artifact tied to $commit." >&2
  exit 1
fi

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

notarize() {
  local asset=$1
  local response="$stage/$(basename "$asset").notary.json"
  xcrun notarytool submit "$asset" --keychain-profile "$profile" --wait --output-format json | tee "$response"
  if [[ $(plutil -extract status raw "$response") != Accepted ]]; then
    local submission
    submission=$(plutil -extract id raw "$response")
    xcrun notarytool log "$submission" --keychain-profile "$profile"
    return 1
  fi
}

ALTO_SIGN_IDENTITY="$identity" ALTO_DIST_DIR="$stage" ./Scripts/build-app.sh
app_name=$(plutil -extract CFBundleName raw Scripts/Info.plist)
version=$(plutil -extract CFBundleShortVersionString raw Scripts/Info.plist)
arch=$(uname -m)
asset_name="${app_name// /-}-v$version-macOS-$arch"
app="$stage/$app_name.app"

ditto -c -k --keepParent "$app" "$stage/submission.zip"
notarize "$stage/submission.zip"
xcrun stapler staple "$app"
xcrun stapler validate "$app"
ditto -c -k --keepParent "$app" "$stage/$asset_name.zip"

ALTO_DIST_DIR="$stage" ./Scripts/package-dmg.sh "$stage"
dmg="$stage/$asset_name.dmg"
codesign --force --sign "$identity" --timestamp --identifier com.altotranscription.updates.disk-image "$dmg"
codesign --verify "$dmg"
notarize "$dmg"
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"

(
  cd "$stage"
  shasum -a 256 "$asset_name.zip" > "$asset_name.zip.sha256"
  shasum -a 256 "$asset_name.dmg" > "$asset_name.dmg.sha256"
  {
    printf 'Commit: %s\n' "$commit"
    xcodebuild -version
    swift --version
  } > BUILD.txt
)
mkdir -p dist/notarized
mv "$stage/$asset_name.zip" "$stage/$asset_name.zip.sha256" \
   "$stage/$asset_name.dmg" "$stage/$asset_name.dmg.sha256" "$stage/BUILD.txt" dist/notarized/
printf 'Notarized release assets: %s/dist/notarized\n' "$PWD"
