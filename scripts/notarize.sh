#!/bin/bash
#
# Submits an already-signed artifact (.app or .dmg) to Apple's notary service and
# staples the resulting ticket, so it launches on other Macs without a Gatekeeper
# prompt — even offline. Run AFTER signing with a Developer ID identity.
#
# Required environment (App-Specific Password flow):
#   MACOS_NOTARY_APPLE_ID   Apple ID email tied to the Developer Program
#   MACOS_NOTARY_TEAM_ID    10-character Team ID
#   MACOS_NOTARY_PWD        app-specific password (appleid.apple.com → Sign-In & Security
#                           → App-Specific Passwords)
#
set -euo pipefail

TARGET="${1:-CloudflareTunnelManager.app}"

: "${MACOS_NOTARY_APPLE_ID:?Set MACOS_NOTARY_APPLE_ID}"
: "${MACOS_NOTARY_TEAM_ID:?Set MACOS_NOTARY_TEAM_ID}"
: "${MACOS_NOTARY_PWD:?Set MACOS_NOTARY_PWD}"

if [[ ! -e "${TARGET}" ]]; then
    echo "✗ Notarization target not found: ${TARGET}" >&2
    exit 1
fi

# notarytool accepts a .dmg/.pkg/.zip directly; a bare .app must be zipped first.
# Either way the ticket is stapled onto the ORIGINAL artifact.
case "${TARGET}" in
    *.dmg|*.pkg|*.zip)
        SUBMIT="${TARGET}"
        ;;
    *)
        SUBMIT="$(mktemp -d)/notarize.zip"
        echo "▶︎ Zipping ${TARGET} for submission…"
        ditto -c -k --keepParent "${TARGET}" "${SUBMIT}"
        ;;
esac

echo "▶︎ Submitting to Apple notary service (can take a few minutes)…"
# notarytool exits 0 once a submission COMPLETES — even when the result is
# "Invalid" — so we must inspect the status ourselves rather than trust $?.
SUB_JSON="$(xcrun notarytool submit "${SUBMIT}" \
    --apple-id "${MACOS_NOTARY_APPLE_ID}" \
    --team-id "${MACOS_NOTARY_TEAM_ID}" \
    --password "${MACOS_NOTARY_PWD}" \
    --output-format json --wait)"
echo "${SUB_JSON}"

flat="$(printf '%s' "${SUB_JSON}" | tr -d '\n')"
STATUS="$(printf '%s' "${flat}" | sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
SUBID="$(printf '%s' "${flat}" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"

if [[ "${STATUS}" != "Accepted" ]]; then
    echo "✗ Notarization not accepted (status: ${STATUS:-unknown})." >&2
    if [[ -n "${SUBID}" ]]; then
        echo "▶︎ Notary log for ${SUBID}:" >&2
        xcrun notarytool log "${SUBID}" \
            --apple-id "${MACOS_NOTARY_APPLE_ID}" \
            --team-id "${MACOS_NOTARY_TEAM_ID}" \
            --password "${MACOS_NOTARY_PWD}" >&2 || true
    fi
    exit 1
fi
echo "✓ Notarization accepted (${SUBID})"

echo "▶︎ Stapling notarization ticket…"
xcrun stapler staple "${TARGET}"
xcrun stapler validate "${TARGET}"
echo "✓ Notarized & stapled ${TARGET}"
