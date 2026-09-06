#!/bin/bash
set -euo pipefail

readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly DIST_DIR="${PROJECT_ROOT}/dist"
readonly APP_NAME="Tread Updater"
readonly APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
readonly CONTENTS_DIR="${APP_BUNDLE}/Contents"
readonly MACOS_DIR="${CONTENTS_DIR}/MacOS"
readonly RESOURCES_DIR="${CONTENTS_DIR}/Resources"
readonly ICONSET_DIR="${DIST_DIR}/AppIcon.iconset"
readonly ICON_FILE="${RESOURCES_DIR}/AppIcon.icns"

fail() {
    echo "error: $*" >&2
    exit 1
}

[[ "${APP_BUNDLE}" == "${PROJECT_ROOT}/dist/"* ]] || fail "Refusing to use an output path outside dist/."

cd "${PROJECT_ROOT}"
mkdir -p "${DIST_DIR}"
rm -rf "${APP_BUNDLE}" "${ICONSET_DIR}"

swift build --configuration release --arch arm64 --arch x86_64
readonly BINARY_DIR="$(swift build --configuration release --arch arm64 --arch x86_64 --show-bin-path)"
readonly EXECUTABLE="${BINARY_DIR}/TreadUpdater"
[[ -f "${EXECUTABLE}" ]] || fail "Swift build did not produce ${EXECUTABLE}."

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}/RepositoryData"
cp "${EXECUTABLE}" "${MACOS_DIR}/TreadUpdater"
cp "${PROJECT_ROOT}/Packaging/Info.plist" "${CONTENTS_DIR}/Info.plist"
ditto "${PROJECT_ROOT}/wheels.json" "${RESOURCES_DIR}/RepositoryData/wheels.json"
ditto "${PROJECT_ROOT}/wheels" "${RESOURCES_DIR}/RepositoryData/wheels"

swift "${PROJECT_ROOT}/scripts/generate-macos-icon.swift" \
    "${PROJECT_ROOT}/Packaging/AppIcon-master.png" \
    "${ICONSET_DIR}"
iconutil --convert icns "${ICONSET_DIR}" --output "${ICON_FILE}"
rm -rf "${ICONSET_DIR}"

codesign --force --sign - --timestamp=none "${APP_BUNDLE}"
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
plutil -lint "${CONTENTS_DIR}/Info.plist" >/dev/null
lipo -archs "${MACOS_DIR}/TreadUpdater" | grep -Eq '(^| )arm64( |$)' || fail "arm64 slice is missing."
lipo -archs "${MACOS_DIR}/TreadUpdater" | grep -Eq '(^| )x86_64( |$)' || fail "x86_64 slice is missing."

echo "Built ${APP_BUNDLE}"
