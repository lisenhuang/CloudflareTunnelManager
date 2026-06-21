#!/bin/bash
#
# Packages a (signed) CloudflareTunnelManager.app into a distributable .dmg with a
# drag-to-Applications layout: opening the disk image shows the app next to an
# "Applications" alias, so users install by dragging the app onto Applications.
#
# Usage:  scripts/make-dmg.sh [APP_PATH] [VERSION]
# Env:    CODESIGN_IDENTITY  optional Developer ID identity to sign the .dmg itself
#                            (sign the image before notarizing it).
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP="${1:-CloudflareTunnelManager.app}"
VERSION="${2:-${APP_VERSION:-dev}}"
VOL_NAME="Cloudflare Tunnel Manager"
DMG="CloudflareTunnelManager-${VERSION}.dmg"

if [[ ! -d "${APP}" ]]; then
    echo "✗ App bundle not found: ${APP}" >&2
    exit 1
fi

# When signing, fail fast if the app isn't already a valid (hardened-runtime)
# signature — otherwise notarization would reject the DMG minutes later.
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    echo "▶︎ Verifying app signature before packaging…"
    codesign --verify --strict --verbose=2 "${APP}"
fi

echo "▶︎ Staging disk-image contents…"
STAGING="$(mktemp -d)"
cp -R "${APP}" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"   # the drag target

echo "▶︎ Creating ${DMG}…"
rm -f "${DMG}"
hdiutil create \
    -volname "${VOL_NAME}" \
    -srcfolder "${STAGING}" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "${DMG}"

rm -rf "${STAGING}"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    echo "▶︎ Signing ${DMG} with Developer ID…"
    codesign --force --timestamp --sign "${CODESIGN_IDENTITY}" "${DMG}"
    codesign --verify --verbose=2 "${DMG}"
fi

echo "✓ Built ${DMG}"
echo "  (open it and drag the app onto Applications)"
