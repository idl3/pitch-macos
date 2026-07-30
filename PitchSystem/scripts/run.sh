#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="PitchSystem"

"${ROOT_DIR}/scripts/package_app.sh" debug >/dev/null
open "${ROOT_DIR}/${APP_NAME}.app"
