#!/usr/bin/env bash
set -euo pipefail

source_app=${1:?iOS app path required}
output=${2:?output directory required}
build_number=${3:?build number required}
identifier=cz.brabal01.kitemapsultimate
plist=/usr/libexec/PlistBuddy
mkdir -p "$output"
output=$(cd "$output" && pwd)
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

for variant in Full SideStore; do
  mkdir -p "$stage/$variant/Payload"
  app="$stage/$variant/Payload/Kite.app"
  ditto "$source_app" "$app"
  "$plist" -c "Set :CFBundleVersion $build_number" "$app/Info.plist"
  test "$("$plist" -c 'Print :CFBundleIdentifier' "$app/Info.plist")" = "$identifier"
  test "$("$plist" -c 'Print :MinimumOSVersion' "$app/Info.plist")" = 16.0
  lipo "$app/Kite" -verify_arch arm64
  xcrun vtool -show-build "$app/Kite" | grep -E 'platform[[:space:]]+IOS[[:space:]]*$'
  test -d "$app/Frameworks/KiteShared.framework"
  lipo "$app/Frameworks/KiteShared.framework/KiteShared" -verify_arch arm64

  if [[ $variant == SideStore ]]; then
    rm -rf "$app/PlugIns"
    "$plist" -c 'Delete :NSSupportsLiveActivities' "$app/Info.plist"
  else
    widget="$app/PlugIns/KiteWidget.appex"
    test "$("$plist" -c 'Print :CFBundleIdentifier' "$widget/Info.plist")" = "$identifier.NavigationWidget"
    "$plist" -c "Set :CFBundleVersion $build_number" "$widget/Info.plist"
    lipo "$widget/KiteWidget" -verify_arch arm64
  fi

  while IFS= read -r -d '' bundle; do
    codesign --force --sign - --timestamp=none "$bundle"
  done < <(find "$app" -mindepth 1 \( -name '*.framework' -o -name '*.dylib' -o -name '*.appex' \) -depth -print0)
  codesign --force --sign - --timestamp=none "$app"
  codesign --verify --deep --strict --verbose=2 "$app"

  ipa="$output/KiteMapsUltimate-$variant.ipa"
  rm -f "$ipa"
  (cd "$stage/$variant" && zip -qr -X "$ipa" Payload)
  unzip -tq "$ipa"
done

(cd "$output" && shasum -a 256 KiteMapsUltimate-*.ipa > SHA256SUMS.txt &&
  shasum -a 256 -c SHA256SUMS.txt && ls -lh KiteMapsUltimate-*.ipa)
