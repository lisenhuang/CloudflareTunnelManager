#!/bin/bash
#
# Builds a release binary and assembles it into a runnable CloudflareTunnelManager.app
# bundle. SwiftPM produces a bare executable; macOS GUI apps need a bundle with an
# Info.plist, so we wrap it here.
#
# Environment overrides (all optional — defaults give a fast local host-arch build):
#   CONFIG=release|debug      build configuration (default: release; positional $1 also works)
#   UNIVERSAL=1               build a universal arm64 + x86_64 binary (CI uses this)
#   APP_VERSION=1.2.3         stamp CFBundleShortVersionString / CFBundleVersion
#   CODESIGN_IDENTITY="..."   Developer ID identity for a real, hardened-runtime
#                             signature (e.g. "Developer ID Application: Jane Doe (ABCDE12345)").
#                             When empty/unset, falls back to an ad-hoc signature.
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="CloudflareTunnelManager"
APP_DIR="${APP_NAME}.app"
CONFIG="${CONFIG:-${1:-release}}"

# Assemble the SwiftPM build flags once so the build and --show-bin-path always agree
# (the products path differs for a universal build vs a single-arch one).
BUILD_FLAGS=(-c "${CONFIG}")
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    BUILD_FLAGS+=(--arch arm64 --arch x86_64)
fi

echo "▶︎ Building (${CONFIG}${UNIVERSAL:+, universal})…"
swift build "${BUILD_FLAGS[@]}"

BIN_PATH="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)/${APP_NAME}"
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

# Stamp the version into the *bundled* Info.plist (never the source one) when provided.
if [[ -n "${APP_VERSION:-}" ]]; then
    echo "▶︎ Stamping version ${APP_VERSION}…"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${APP_VERSION}" "${APP_DIR}/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${APP_VERSION}" "${APP_DIR}/Contents/Info.plist"
fi

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    # Developer ID signature with hardened runtime — required for notarization.
    echo "▶︎ Signing with Developer ID (hardened runtime)…"
    codesign --force --options runtime --timestamp \
        --sign "${CODESIGN_IDENTITY}" "${APP_DIR}"
    codesign --verify --strict --verbose=2 "${APP_DIR}"
else
    # Ad-hoc signature so Keychain access and outbound networking work locally
    # without Gatekeeper prompts. Such a build is NOT notarized — other Macs will
    # quarantine it on download (see README "Continuous delivery").
    echo "▶︎ Ad-hoc signing (no CODESIGN_IDENTITY set)…"
    codesign --force --sign - "${APP_DIR}" 2>/dev/null || \
        echo "  (codesign skipped — install Command Line Tools to sign)"
fi

echo "✓ Built ${APP_DIR}"
echo "  Run with:  open ${APP_DIR}"
