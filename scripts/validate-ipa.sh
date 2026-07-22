#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ $# -eq 1 ]] || fail "usage: scripts/validate-ipa.sh path/to/GTA6Countdown-TrollStore.ipa"
ipa="$1"
[[ -f "$ipa" ]] || fail "IPA does not exist: $ipa"
[[ -s "$ipa" ]] || fail "IPA is empty: $ipa"
command -v python3 >/dev/null 2>&1 || fail "python3 is required to inspect ZIP and binary plist files"

python3 - "$ipa" <<'PY'
import pathlib
import plistlib
import sys
import zipfile

EXPECTED_APP_ID = "com.jaysuen.gta6countdown"
EXPECTED_WIDGET_ID = "com.jaysuen.gta6countdown.widget"
EXPECTED_MINIMUM = "16.0"
EXPECTED_EXTENSION_POINT = "com.apple.widgetkit-extension"

def fail(message):
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)

ipa_path = pathlib.Path(sys.argv[1])
try:
    archive = zipfile.ZipFile(ipa_path)
    bad_member = archive.testzip()
except (OSError, zipfile.BadZipFile) as error:
    fail(f"IPA is not a readable ZIP archive: {error}")
if bad_member:
    fail(f"ZIP member failed its CRC check: {bad_member}")

members = archive.infolist()
names = [member.filename for member in members]
if not names:
    fail("IPA ZIP contains no files")
if len(names) != len(set(names)):
    fail("IPA contains duplicate ZIP member names")
if any(name.startswith("/") or ".." in pathlib.PurePosixPath(name).parts for name in names):
    fail("IPA contains an unsafe absolute or parent-relative path")

main_roots = {
    "/".join(pathlib.PurePosixPath(name).parts[:2]) + "/"
    for name in names
    if len(pathlib.PurePosixPath(name).parts) >= 2
    and pathlib.PurePosixPath(name).parts[0] == "Payload"
    and pathlib.PurePosixPath(name).parts[1].endswith(".app")
}
if len(main_roots) != 1:
    fail(f"expected exactly one Payload main app, found {len(main_roots)}")
app_root = next(iter(main_roots))
main_info = app_root + "Info.plist"

def read_plist(name, label):
    try:
        return plistlib.loads(archive.read(name))
    except KeyError:
        fail(f"missing {label}: {name}")
    except Exception as error:
        fail(f"cannot parse {label} {name}: {error}")

def require_nonempty(name, label):
    try:
        info = archive.getinfo(name)
    except KeyError:
        fail(f"missing {label}: {name}")
    if info.is_dir() or info.file_size <= 0:
        fail(f"{label} is empty: {name}")

main = read_plist(main_info, "main app Info.plist")
if main.get("CFBundleIdentifier") != EXPECTED_APP_ID:
    fail(f"main bundle id must be {EXPECTED_APP_ID!r}, got {main.get('CFBundleIdentifier')!r}")
if main.get("MinimumOSVersion") != EXPECTED_MINIMUM:
    fail(f"main MinimumOSVersion must be {EXPECTED_MINIMUM!r}, got {main.get('MinimumOSVersion')!r}")
main_executable = main.get("CFBundleExecutable")
if not isinstance(main_executable, str) or not main_executable or "/" in main_executable:
    fail("main CFBundleExecutable is missing or invalid")
require_nonempty(app_root + main_executable, "main executable")
require_nonempty(app_root + "Assets.car", "compiled asset catalog")
require_nonempty(app_root + "news-payload.json", "bundled fallback news feed")

plugin_prefix = pathlib.PurePosixPath(app_root + "PlugIns").parts
widget_roots = {
    "/".join(pathlib.PurePosixPath(name).parts[:len(plugin_prefix) + 1]) + "/"
    for name in names
    if len(pathlib.PurePosixPath(name).parts) >= len(plugin_prefix) + 1
    and pathlib.PurePosixPath(name).parts[:len(plugin_prefix)] == plugin_prefix
    and pathlib.PurePosixPath(name).parts[len(plugin_prefix)].endswith(".appex")
}
if len(widget_roots) != 1:
    fail(f"expected exactly one embedded Widget extension, found {len(widget_roots)}")
widget_root = next(iter(widget_roots))
widget_info = widget_root + "Info.plist"
widget = read_plist(widget_info, "Widget Info.plist")
if widget.get("CFBundleIdentifier") != EXPECTED_WIDGET_ID:
    fail(f"Widget bundle id must be {EXPECTED_WIDGET_ID!r}, got {widget.get('CFBundleIdentifier')!r}")
if widget.get("MinimumOSVersion") != EXPECTED_MINIMUM:
    fail(f"Widget MinimumOSVersion must be {EXPECTED_MINIMUM!r}, got {widget.get('MinimumOSVersion')!r}")
extension_point = widget.get("NSExtension", {}).get("NSExtensionPointIdentifier")
if extension_point != EXPECTED_EXTENSION_POINT:
    fail(f"Widget extension point must be {EXPECTED_EXTENSION_POINT!r}, got {extension_point!r}")
widget_executable = widget.get("CFBundleExecutable")
if not isinstance(widget_executable, str) or not widget_executable or "/" in widget_executable:
    fail("Widget CFBundleExecutable is missing or invalid")
require_nonempty(widget_root + widget_executable, "Widget executable")

print(f"PASS: valid TrollStore IPA contract ({ipa_path.name})")
print(f"  app: {main['CFBundleIdentifier']} / iOS {main['MinimumOSVersion']}")
print(f"  widget: {widget['CFBundleIdentifier']} / {extension_point}")
PY
