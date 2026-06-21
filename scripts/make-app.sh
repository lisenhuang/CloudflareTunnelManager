#!/bin/bash
#
# Builds a release binary and assembles it into a runnable CloudflareTunnelManager.app
# bundle. SwiftPM produces a bare executable; macOS GUI apps need a bundle with an
# Info.plist, so we wrap it here.
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="CloudflareTunnelManager"
APP_DIR="${APP_NAME}.app"
CONFIG="${1:-release}"

echo "▶︎ Building (${CONFIG})…"
swift build -c "${CONFIG}"

BIN_PATH="$(swift build -c "${CONFIG}" --show-bin-path)/${APP_NAME}"
if [[ ! -x "${BIN_PATH}" ]]; then
    echo "✗ Built binary not found at ${BIN_PATH}" >&2
    exit 1
fi

echo "▶︎ Assembling ${APP_DIR}…"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "Resources/Info.plist" "${APP_DIR}/Contents/Info.plist"
cp "${BIN_PATH}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

# Ad-hoc code signature so Keychain access and outbound networking work locally
# without Gatekeeper prompts. For distribution, replace with a Developer ID
# signature + notarization (see README).
echo "▶︎ Ad-hoc signing…"
codesign --force --sign - "${APP_DIR}" 2>/dev/null || \
    echo "  (codesign skipped — install Command Line Tools to sign)"

echo "✓ Built ${APP_DIR}"
echo "  Run with:  open ${APP_DIR}"
