#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ $# -ge 1 && $# -le 2 ]] || fail "usage: scripts/package-ipa.sh path/to/GTA6Countdown.app [output.ipa]"
[[ -d "$1" ]] || fail "built app bundle does not exist: $1"
app="$(cd "$(dirname "$1")" 2>/dev/null && pwd)/$(basename "$1")"
[[ "$app" == *.app ]] || fail "input must be a .app bundle"

root="$(cd "$(dirname "$0")/.." && pwd)"
output="${2:-$root/dist/GTA6Countdown-TrollStore.ipa}"
case "$output" in
  *.ipa) ;;
  *) fail "output must use the .ipa extension" ;;
esac
mkdir -p "$(dirname "$output")"
output="$(cd "$(dirname "$output")" && pwd)/$(basename "$output")"

widget="$app/PlugIns/GTA6CountdownWidget.appex"
[[ -d "$widget" ]] || fail "built app does not embed PlugIns/GTA6CountdownWidget.appex"

if command -v codesign >/dev/null 2>&1; then
  widget_entitlements="$root/GTA6CountdownWidgets/GTA6CountdownWidgets.entitlements"
  app_entitlements="$root/GTA6Countdown/GTA6Countdown.entitlements"
  widget_args=(--force --sign - --timestamp=none --generate-entitlement-der)
  app_args=(--force --sign - --timestamp=none --generate-entitlement-der)
  [[ -f "$widget_entitlements" ]] && widget_args+=(--entitlements "$widget_entitlements")
  [[ -f "$app_entitlements" ]] && app_args+=(--entitlements "$app_entitlements")
  codesign "${widget_args[@]}" "$widget"
  codesign "${app_args[@]}" "$app"
  codesign --verify --deep --strict "$app"
  echo "Ad-hoc signed Widget first, then main app (no distribution identity used)."
else
  echo "WARNING: codesign is unavailable; packaging without an ad-hoc signature." >&2
fi

staging="$(mktemp -d "${TMPDIR:-/tmp}/gta6-ipa-package.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/Payload"
if command -v ditto >/dev/null 2>&1; then
  ditto "$app" "$staging/Payload/$(basename "$app")"
else
  cp -R "$app" "$staging/Payload/"
fi

rm -f "$output"
if command -v ditto >/dev/null 2>&1; then
  (cd "$staging" && ditto -c -k --sequesterRsrc --keepParent Payload "$output")
elif command -v zip >/dev/null 2>&1; then
  (cd "$staging" && zip -qry "$output" Payload)
else
  fail "neither ditto nor zip is available to create the IPA"
fi

"$root/scripts/validate-ipa.sh" "$output"
echo "Created TrollStore-targeted IPA: $output"
