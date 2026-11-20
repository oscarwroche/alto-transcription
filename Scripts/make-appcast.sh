#!/bin/bash
set -euo pipefail

if [[ $# != 3 ]]; then
  echo "Usage: $0 <update.zip> <Sparkle sign_update path> <appcast.xml>" >&2
  exit 1
fi

archive=$1
sign_update=$2
appcast=$3
plist="$(dirname "$0")/Info.plist"
app_name=$(plutil -extract CFBundleName raw "$plist")
version=$(plutil -extract CFBundleShortVersionString raw "$plist")
build=$(plutil -extract CFBundleVersion raw "$plist")
minimum_os=$(plutil -extract LSMinimumSystemVersion raw "$plist")
asset=$(basename "$archive")
if [[ "$asset" != "${app_name// /-}-v$version-macOS-arm64.zip" ]]; then
  echo "Expected the release ZIP for version $version." >&2
  exit 1
fi

account="com.altotranscription.updates"
signature=$("$sign_update" --account "$account" -p "$archive")
bytes=$(stat -f %z "$archive")
base="https://github.com/oscarwroche/body-and-soul"
mkdir -p "$(dirname "$appcast")"
cat >"$appcast" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Body and Soul Updates</title>
    <item>
      <title>Body and Soul $version</title>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$minimum_os</sparkle:minimumSystemVersion>
      <enclosure url="$base/releases/download/v$version/$asset"
                 sparkle:edSignature="$signature" length="$bytes" type="application/zip"/>
    </item>
  </channel>
</rss>
EOF
"$sign_update" --account "$account" "$appcast"
"$sign_update" --account "$account" --verify "$archive" "$signature"
"$sign_update" --account "$account" --verify "$appcast"
