#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
configuration="${1:-release}"
app_dir="$project_dir/dist/Whatnote.app"
contents_dir="$app_dir/Contents"
marketing_version="${MARKETING_VERSION:-1.2.2}"
build_number="${BUILD_NUMBER:-5}"
bundle_identifier="${BUNDLE_IDENTIFIER:-com.yx1100.whatnote}"
# A self-signed certificate named "Whatnote Local Signing" in the login keychain gives every
# build the same identity, so macOS keeps permissions such as Screen Recording across builds.
local_identity="Whatnote Local Signing"
if [[ -z "${CODESIGN_IDENTITY:-}" ]] && security find-certificate -c "$local_identity" >/dev/null 2>&1; then
  CODESIGN_IDENTITY="$local_identity"
fi
codesign_identity="${CODESIGN_IDENTITY:--}"

if [[ ! "$marketing_version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  print -u2 "MARKETING_VERSION must use numeric SemVer (X.Y.Z): $marketing_version"
  exit 1
fi
if [[ ! "$build_number" =~ '^[0-9]+$' ]]; then
  print -u2 "BUILD_NUMBER must be a positive integer: $build_number"
  exit 1
fi

cd "$project_dir"
rm -rf "$app_dir"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"

# Whatnote (随便记) ships for Apple Silicon only.
swift build -c "$configuration" --arch arm64
binary_path="$(swift build -c "$configuration" --arch arm64 --show-bin-path)/Whatnote"
cp "$binary_path" "$contents_dir/MacOS/Whatnote"

# App icon: a light and a dark variant. The .icns (light) works everywhere;
# with full Xcode installed, an asset catalog adds the dark variant so the icon
# follows the system appearance in Finder, Launchpad and System Settings.
icon_root="$project_dir/.build/icon"
rm -rf "$icon_root"
mkdir -p "$icon_root"
swift "$project_dir/Tools/GenerateIcon.swift" "$icon_root/light.png" light
swift "$project_dir/Tools/GenerateIcon.swift" "$icon_root/dark.png" dark

icon_work="$icon_root/Whatnote.iconset"
mkdir -p "$icon_work"
for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" "512 512x512" "1024 512x512@2x"; do
  pixels="${spec%% *}"
  filename="${spec#* }"
  sips -z "$pixels" "$pixels" "$icon_root/light.png" --out "$icon_work/icon_$filename.png" >/dev/null
done
iconutil -c icns "$icon_work" -o "$contents_dir/Resources/Whatnote.icns"

has_icon_catalog=false
if xcrun --find actool >/dev/null 2>&1; then
  iconset="$icon_root/Assets.xcassets/AppIcon.appiconset"
  mkdir -p "$iconset"
  print -r -- '{ "info" : { "author" : "xcode", "version" : 1 } }' > "$icon_root/Assets.xcassets/Contents.json"
  entries=()
  for appearance in light dark; do
    for size in 16 32 128 256 512; do
      for scale in 1 2; do
        pixels=$(( size * scale ))
        file="${appearance}_${size}@${scale}x.png"
        sips -z "$pixels" "$pixels" "$icon_root/$appearance.png" --out "$iconset/$file" >/dev/null
        extra=""
        if [[ "$appearance" == "dark" ]]; then
          extra='"appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], '
        fi
        entries+=("{ ${extra}\"filename\" : \"$file\", \"idiom\" : \"mac\", \"scale\" : \"${scale}x\", \"size\" : \"${size}x${size}\" }")
      done
    done
  done
  print -r -- "{ \"images\" : [ ${(j:, :)entries} ], \"info\" : { \"author\" : \"xcode\", \"version\" : 1 } }" > "$iconset/Contents.json"
  if xcrun actool "$icon_root/Assets.xcassets" \
      --compile "$contents_dir/Resources" \
      --platform macosx \
      --minimum-deployment-target 11.0 \
      --app-icon AppIcon \
      --output-partial-info-plist "$icon_root/partial.plist" >"$icon_root/actool.log" 2>&1; then
    has_icon_catalog=true
  else
    print -u2 "warning: could not compile the light/dark app icon, using the light icon only (see $icon_root/actool.log)"
  fi
else
  print -u2 "note: install Xcode to get an app icon that follows light and dark mode"
fi

plutil -create xml1 "$contents_dir/Info.plist"
plutil -insert CFBundleDisplayName -string "Whatnote" "$contents_dir/Info.plist"
plutil -insert CFBundleExecutable -string "Whatnote" "$contents_dir/Info.plist"
plutil -insert CFBundleIconFile -string "Whatnote" "$contents_dir/Info.plist"
if [[ "$has_icon_catalog" == true ]]; then
  plutil -insert CFBundleIconName -string "AppIcon" "$contents_dir/Info.plist"
fi
plutil -insert CFBundleIdentifier -string "$bundle_identifier" "$contents_dir/Info.plist"
plutil -insert CFBundleInfoDictionaryVersion -string "6.0" "$contents_dir/Info.plist"
plutil -insert CFBundleName -string "Whatnote" "$contents_dir/Info.plist"
plutil -insert CFBundlePackageType -string "APPL" "$contents_dir/Info.plist"
plutil -insert CFBundleShortVersionString -string "$marketing_version" "$contents_dir/Info.plist"
plutil -insert CFBundleVersion -string "$build_number" "$contents_dir/Info.plist"
plutil -insert CFBundleDevelopmentRegion -string "zh-Hans" "$contents_dir/Info.plist"
plutil -insert LSHasLocalizedDisplayName -bool true "$contents_dir/Info.plist"
plutil -insert LSMinimumSystemVersion -string "11.0" "$contents_dir/Info.plist"
plutil -insert LSArchitecturePriority -json '["arm64"]' "$contents_dir/Info.plist"
plutil -insert LSUIElement -bool true "$contents_dir/Info.plist"
plutil -insert NSUserNotificationAlertStyle -string "alert" "$contents_dir/Info.plist"

# Finder, Launchpad and Login Items show the Chinese name 随便记.
localized_dir="$contents_dir/Resources/zh-Hans.lproj"
mkdir -p "$localized_dir"
print -r -- '"CFBundleDisplayName" = "随便记";
"CFBundleName" = "随便记";' > "$localized_dir/InfoPlist.strings"

codesign_options=(--force --sign "$codesign_identity")
if [[ "$codesign_identity" != "-" && "$codesign_identity" != "$local_identity" ]]; then
  codesign_options+=(--options runtime --timestamp)
fi

codesign "${codesign_options[@]}" "$app_dir"
codesign --verify --deep --strict "$app_dir"
echo "$app_dir"
