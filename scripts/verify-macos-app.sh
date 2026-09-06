#!/bin/bash
set -euo pipefail

readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly APP_BUNDLE="${1:-${PROJECT_ROOT}/dist/Tread Updater.app}"
readonly CONTENTS_DIR="${APP_BUNDLE}/Contents"
readonly EXECUTABLE="${CONTENTS_DIR}/MacOS/TreadUpdater"
readonly RESOURCE_ROOT="${CONTENTS_DIR}/Resources/RepositoryData"

fail() {
    echo "error: $*" >&2
    exit 1
}

[[ -d "${APP_BUNDLE}" ]] || fail "App bundle not found: ${APP_BUNDLE}"
[[ -f "${CONTENTS_DIR}/Info.plist" ]] || fail "Info.plist is missing."
[[ -f "${EXECUTABLE}" ]] || fail "Application executable is missing."
[[ -f "${CONTENTS_DIR}/Resources/AppIcon.icns" ]] || fail "App icon is missing."
[[ -f "${RESOURCE_ROOT}/wheels.json" ]] || fail "Bundled wheels.json is missing."
[[ -d "${RESOURCE_ROOT}/wheels" ]] || fail "Bundled wheels directory is missing."

plutil -lint "${CONTENTS_DIR}/Info.plist" >/dev/null
[[ "$(plutil -extract CFBundleIdentifier raw "${CONTENTS_DIR}/Info.plist")" == "jp.tomonariutsuno.tread-updater" ]] || fail "Unexpected bundle identifier."
[[ "$(plutil -extract CFBundleShortVersionString raw "${CONTENTS_DIR}/Info.plist")" == "1.0.0" ]] || fail "Unexpected app version."
[[ "$(plutil -extract LSMinimumSystemVersion raw "${CONTENTS_DIR}/Info.plist")" == "13.0" ]] || fail "Unexpected minimum macOS version."

readonly ARCHITECTURES="$(lipo -archs "${EXECUTABLE}")"
[[ " ${ARCHITECTURES} " == *" arm64 "* ]] || fail "arm64 slice is missing."
[[ " ${ARCHITECTURES} " == *" x86_64 "* ]] || fail "x86_64 slice is missing."
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

readonly EXPECTED_WHEEL_COUNT="$(python3 - <<'PY' "${RESOURCE_ROOT}/wheels.json" "${RESOURCE_ROOT}/wheels"
import json
import pathlib
import sys

catalog = json.loads(pathlib.Path(sys.argv[1]).read_text())
wheels = catalog["wheels"]
images = list(pathlib.Path(sys.argv[2]).glob("w*.png"))
if len(wheels) != 36 or len(images) != 36:
    raise SystemExit(f"expected 36 wheel records and images, got {len(wheels)} records and {len(images)} images")
print(len(wheels))
PY
)"

echo "Verified ${APP_BUNDLE} (${ARCHITECTURES}; ${EXPECTED_WHEEL_COUNT} bundled wheel records)"
