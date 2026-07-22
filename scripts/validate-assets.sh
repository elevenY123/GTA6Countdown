#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
catalog="$repo_root/GTA6Countdown/Assets.xcassets"

fail() {
  echo "asset validation failed: $*" >&2
  exit 1
}

for dependency in rg identify awk cmp mktemp wc tr; do
  command -v "$dependency" >/dev/null 2>&1 || fail "required command is unavailable: $dependency"
done

if command -v sha256sum >/dev/null 2>&1; then
  hash_file() {
    sha256sum "$1" | awk '{print $1}'
  }
elif command -v shasum >/dev/null 2>&1; then
  hash_file() {
    shasum -a 256 "$1" | awk '{print $1}'
  }
else
  fail "required SHA-256 tool is unavailable: install sha256sum or use macOS shasum"
fi

required_sets=(
  "AppIcon.appiconset"
  "HeroLight.imageset"
  "HeroDark.imageset"
  "NewsPlaceholder.imageset"
)

for set_name in "${required_sets[@]}"; do
  [[ -f "$catalog/$set_name/Contents.json" ]] || fail "missing $set_name/Contents.json"
done

[[ -f "$repo_root/ASSET_SOURCES.md" ]] || fail "missing ASSET_SOURCES.md"
[[ -f "$repo_root/THIRD_PARTY_NOTICES.md" ]] || fail "missing THIRD_PARTY_NOTICES.md"

icon_dir="$catalog/AppIcon.appiconset"
while IFS='|' read -r filename expected_dimensions; do
  path="$icon_dir/$filename"
  [[ -f "$path" ]] || fail "missing app icon $filename"
  dimensions="$(identify -format '%wx%h' "$path")"
  [[ "$dimensions" == "$expected_dimensions" ]] || fail "$filename is $dimensions, expected $expected_dimensions"
  channels="$(identify -format '%[channels]' "$path" | tr '[:upper:]' '[:lower:]')"
  [[ "$channels" != *a* ]] || fail "$filename contains an alpha channel"
done <<'ICON_DIMENSIONS'
AppIcon-20@2x.png|40x40
AppIcon-20@3x.png|60x60
AppIcon-29@2x.png|58x58
AppIcon-29@3x.png|87x87
AppIcon-40@2x.png|80x80
AppIcon-40@3x.png|120x120
AppIcon-60@2x.png|120x120
AppIcon-60@3x.png|180x180
AppIcon-1024.png|1024x1024
ICON_DIMENSIONS

for set_name in HeroLight HeroDark NewsPlaceholder; do
  for scale in 1 2 3; do
    file="$catalog/$set_name.imageset/$set_name@${scale}x.jpg"
    [[ -f "$file" ]] || fail "missing $set_name@${scale}x.jpg"
  done
done

hero_light="$(identify -format '%wx%h' "$catalog/HeroLight.imageset/HeroLight@3x.jpg")"
hero_dark="$(identify -format '%wx%h' "$catalog/HeroDark.imageset/HeroDark@3x.jpg")"
[[ "$hero_light" == "1170x1560" ]] || fail "HeroLight@3x.jpg is $hero_light, expected 1170x1560"
[[ "$hero_dark" == "1170x1560" ]] || fail "HeroDark@3x.jpg is $hero_dark, expected 1170x1560"

for hero in "$catalog/HeroLight.imageset/HeroLight@3x.jpg" "$catalog/HeroDark.imageset/HeroDark@3x.jpg"; do
  size="$(wc -c < "$hero")"
  (( size <= 900000 )) || fail "$(basename "$hero") exceeds 900 KB"
done

rg -q 'Rockstar Games' "$repo_root/ASSET_SOURCES.md" || fail "source manifest lacks Rockstar attribution"
rg -q 'https://www\.rockstargames\.com/' "$repo_root/ASSET_SOURCES.md" || fail "source manifest lacks an official Rockstar URL"
rg -q '非官方' "$repo_root/THIRD_PARTY_NOTICES.md" || fail "notices lack non-official disclaimer"

license_copy="$(mktemp)"
trap 'rm -f "$license_copy"' EXIT
awk '/^```text$/{capture=1; next} capture && /^```$/{exit} capture {print}' \
  "$repo_root/THIRD_PARTY_NOTICES.md" > "$license_copy"
expected_license_sha="960f7fc16d8baa126802316a7df9078a383af4fb6bc60033adb28e85c08d5e5e"
actual_license_sha="$(hash_file "$license_copy")"
[[ "$actual_license_sha" == "$expected_license_sha" ]] || fail "opencc-js license text is incomplete or modified"
if [[ -f "$repo_root/backend/node_modules/opencc-js/LICENSE" ]]; then
  cmp -s "$license_copy" "$repo_root/backend/node_modules/opencc-js/LICENSE" || fail "bundled opencc-js license differs from installed upstream license"
fi

echo "asset validation passed"
