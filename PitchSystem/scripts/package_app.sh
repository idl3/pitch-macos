#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="KBear"
BUNDLE_ID="codes.ernest.kbear"
BUILD_MODE="${1:-debug}"

if [[ "${BUILD_MODE}" != "debug" && "${BUILD_MODE}" != "release" ]]; then
    echo "Usage: $(basename "$0") [debug|release]" >&2
    exit 1
fi

cd "${ROOT_DIR}"

export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/swiftpm-module-cache"
export XDG_CACHE_HOME="${TMPDIR:-/tmp}/swiftpm-cache"
export SWIFTPM_DISABLE_SANDBOX=1

swift build -c "${BUILD_MODE}"

BUILD_DIR="${ROOT_DIR}/.build/${BUILD_MODE}"
PRODUCT_PATH="${BUILD_DIR}/${APP_NAME}"
APP_BUNDLE="${ROOT_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"

if [[ ! -f "${PRODUCT_PATH}" ]]; then
    echo "ERROR: built product not found at ${PRODUCT_PATH}" >&2
    exit 1
fi

rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${CONTENTS_DIR}/Resources"
cp "${PRODUCT_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"
cp "${ROOT_DIR}/Info.plist" "${CONTENTS_DIR}/Info.plist"
if [[ -d "${ROOT_DIR}/Resources" ]]; then
    cp -R "${ROOT_DIR}/Resources/" "${CONTENTS_DIR}/Resources/"
fi

if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "${APP_BUNDLE}" >/dev/null 2>&1 || true
fi

echo "${APP_BUNDLE}"
