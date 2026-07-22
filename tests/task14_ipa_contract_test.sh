#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
validator="$root/scripts/validate-ipa.sh"
fixtures="$(mktemp -d "${TMPDIR:-/tmp}/gta6-ipa-contract.XXXXXX")"
trap 'rm -rf "$fixtures"' EXIT

python3 - "$fixtures" <<'PY'
import io
import pathlib
import plistlib
import sys
import zipfile

root = pathlib.Path(sys.argv[1])

def plist(values):
    output = io.BytesIO()
    plistlib.dump(values, output, fmt=plistlib.FMT_BINARY)
    return output.getvalue()

def make(name, *, main=True, widget=True, minimum="16.0"):
    with zipfile.ZipFile(root / name, "w", zipfile.ZIP_DEFLATED) as ipa:
        if not main:
            ipa.writestr("README.txt", "not an app")
            return
        app = "Payload/GTA6Countdown.app/"
        ipa.writestr(app + "Info.plist", plist({
            "CFBundleIdentifier": "com.jaysuen.gta6countdown",
            "CFBundleExecutable": "GTA6Countdown",
            "MinimumOSVersion": minimum,
        }))
        ipa.writestr(app + "GTA6Countdown", b"fake-mach-o-main")
        ipa.writestr(app + "Assets.car", b"fake-asset-catalog")
        ipa.writestr(app + "news-payload.json", b"{}")
        if widget:
            extension = app + "PlugIns/GTA6CountdownWidget.appex/"
            ipa.writestr(extension + "Info.plist", plist({
                "CFBundleIdentifier": "com.jaysuen.gta6countdown.widget",
                "CFBundleExecutable": "GTA6CountdownWidget",
                "MinimumOSVersion": minimum,
                "NSExtension": {
                    "NSExtensionPointIdentifier": "com.apple.widgetkit-extension"
                },
            }))
            ipa.writestr(extension + "GTA6CountdownWidget", b"fake-mach-o-widget")

with zipfile.ZipFile(root / "empty.ipa", "w"):
    pass
make("missing-main.ipa", main=False)
make("missing-widget.ipa", widget=False)
make("wrong-minimum.ipa", minimum="17.0")
make("valid.ipa")

app = root / "Release-iphoneos" / "GTA6Countdown.app"
extension = app / "PlugIns" / "GTA6CountdownWidget.appex"
extension.mkdir(parents=True)
(app / "Info.plist").write_bytes(plist({
    "CFBundleIdentifier": "com.jaysuen.gta6countdown",
    "CFBundleExecutable": "GTA6Countdown",
    "MinimumOSVersion": "16.0",
}))
(app / "GTA6Countdown").write_bytes(b"fake-mach-o-main")
(app / "Assets.car").write_bytes(b"fake-asset-catalog")
(app / "news-payload.json").write_bytes(b"{}")
(extension / "Info.plist").write_bytes(plist({
    "CFBundleIdentifier": "com.jaysuen.gta6countdown.widget",
    "CFBundleExecutable": "GTA6CountdownWidget",
    "MinimumOSVersion": "16.0",
    "NSExtension": {"NSExtensionPointIdentifier": "com.apple.widgetkit-extension"},
}))
(extension / "GTA6CountdownWidget").write_bytes(b"fake-mach-o-widget")
PY

expect_rejected() {
  local fixture="$1"
  if "$validator" "$fixtures/$fixture" >"$fixtures/output.log" 2>&1; then
    echo "FAIL: $fixture should have been rejected" >&2
    exit 1
  fi
  if ! grep -q '^FAIL:' "$fixtures/output.log"; then
    echo "FAIL: $fixture did not produce a clear validation error" >&2
    cat "$fixtures/output.log" >&2
    exit 1
  fi
}

expect_rejected empty.ipa
expect_rejected missing-main.ipa
expect_rejected missing-widget.ipa
expect_rejected wrong-minimum.ipa

"$validator" "$fixtures/valid.ipa"
"$root/scripts/package-ipa.sh" \
  "$fixtures/Release-iphoneos/GTA6Countdown.app" \
  "$fixtures/GTA6Countdown-TrollStore.ipa"
echo "PASS: IPA validator rejects malformed packages and accepts the contract fixture"
