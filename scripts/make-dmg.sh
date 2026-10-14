#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/dist/Whatnote.app"
version="${1:-${MARKETING_VERSION:-}}"

if [ -z "$version" ]; then
  echo "usage: $0 <version>" >&2
  exit 1
fi
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "version must be numeric (X.Y or X.Y.Z): $version" >&2
  exit 1
fi
if [ ! -d "$app" ]; then
  echo "Whatnote.app is missing; run scripts/build-app.sh first" >&2
  exit 1
fi
if [ ! -f "$app/Contents/Info.plist" ]; then
  echo "Whatnote.app is incomplete; run scripts/build-app.sh again" >&2
  exit 1
fi
app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
if [ "$app_version" != "$version" ]; then
  echo "DMG version $version does not match Whatnote.app version $app_version" >&2
  exit 1
fi

output="$root/dist/Whatnote-v${version}-macOS-arm64.dmg"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

ditto "$app" "$stage/Whatnote.app"
ln -s /Applications "$stage/Applications"

rm -f "$output"
hdiutil create \
  -volname "随便记" \
  -srcfolder "$stage" \
  -format UDZO \
  -ov \
  "$output" >/dev/null

hdiutil imageinfo "$output" >/dev/null
echo "$output"
