#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Tonos"

cd "${ROOT_DIR}"

# 1. Build and package a release .app.
"${ROOT_DIR}/scripts/package_app.sh" release

# 2. Stage the app with a friendly installer layout.
STAGING_DIR="${ROOT_DIR}/.dmg-staging"
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"
cp -R "${ROOT_DIR}/${APP_NAME}.app" "${STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGING_DIR}/Applications"

# 3. Create a compressed DMG.
DMG_PATH="${ROOT_DIR}/${APP_NAME}.dmg"
rm -f "${DMG_PATH}"

hdiutil create \
    -srcfolder "${STAGING_DIR}" \
    -volname "${APP_NAME}" \
    -fs HFS+ \
    -format UDZO \
    -o "${DMG_PATH}"

# 4. Clean up staging.
rm -rf "${STAGING_DIR}"

echo "${DMG_PATH}"
