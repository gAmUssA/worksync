#!/bin/bash
# build-app.sh — release build + WorkSync.app assembly + codesign + tarball.
#
# Usage:
#   scripts/build-app.sh [--identity "IDENTITY"] [--adhoc] [--no-tar]
#
# The bundle is REQUIRED, not cosmetic (SPEC §3.1): UNUserNotificationCenter,
# SMAppService.mainApp, and LSUIElement all need a genuine registered app bundle.
#
# Signing: a stable identity keeps the TCC calendar grant across rebuilds.
# Ad-hoc signatures pin the designated requirement to a per-build cdhash, so
# every rebuild resets calendar permission and Gatekeeper approval — use
# --adhoc only for CI artifacts that users will re-sign locally.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="WorkSync"
BUNDLE="build/${APP_NAME}.app"
IDENTITY=""
ADHOC=0
MAKE_TAR=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --identity) IDENTITY="$2"; shift 2 ;;
    --adhoc)    ADHOC=1; shift ;;
    --no-tar)   MAKE_TAR=0; shift ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$IDENTITY" && "$ADHOC" -eq 0 ]]; then
  # Prefer a stable identity if one exists. Select by SHA-1 hash, not name —
  # duplicate same-named certs in the keychain make the name ambiguous.
  # NEVER auto-select 'Apple Development' / 'Apple Distribution': without an
  # embedded provisioning profile AMFI rejects those signatures at exec
  # (error -420 "signature invalid") and the process is SIGKILLed.
  IDENTITY=$(security find-identity -p codesigning -v 2>/dev/null \
    | grep -E 'Developer ID Application|WorkSync Dev' \
    | head -1 | awk '{print $2}' || true)
  if [[ -z "$IDENTITY" ]]; then
    echo "No stable codesigning identity found; falling back to ad-hoc." >&2
    echo "NOTE: ad-hoc signatures reset the TCC calendar grant on every rebuild." >&2
    ADHOC=1
  fi
fi

VERSION=$(git describe --tags --always 2>/dev/null || echo "0.1.0-dev")

echo "==> swift build -c release"
swift build -c release

echo "==> assembling ${BUNDLE}"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp .build/release/worksync "$BUNDLE/Contents/MacOS/worksync"

# SwiftPM resource bundles (Bundle.module traps at runtime without them).
shopt -s nullglob
for rb in .build/release/*.bundle; do
  cp -R "$rb" "$BUNDLE/Contents/Resources/"
done
shopt -u nullglob

cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"

echo "==> codesign"
if [[ "$ADHOC" -eq 1 ]]; then
  codesign --force --sign - --timestamp=none \
    --entitlements Resources/worksync.entitlements "$BUNDLE"
else
  # Never --deep (deprecated for signing since macOS 13); nothing nested to sign.
  codesign --force --sign "$IDENTITY" --timestamp --options runtime \
    --entitlements Resources/worksync.entitlements "$BUNDLE"
fi

echo "==> verifying signature"
codesign --verify --strict "$BUNDLE"
DR=$(codesign -d -r- "$BUNDLE" 2>&1 | grep '^designated' || true)
echo "    $DR"
if [[ "$ADHOC" -eq 0 ]]; then
  # A bare-cdhash designated requirement means the identity was NOT picked up:
  # TCC and notification grants would reset on every rebuild (SPEC §3).
  if echo "$DR" | grep -q 'cdhash' && ! echo "$DR" | grep -q 'identifier'; then
    echo "ERROR: designated requirement is a bare cdhash — stable identity not applied." >&2
    exit 1
  fi
fi

echo "==> registering with LaunchServices"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -f "$BUNDLE"

if [[ "$MAKE_TAR" -eq 1 ]]; then
  ARCH=$(uname -m)
  TARBALL="build/${APP_NAME}-${VERSION}-${ARCH}.tar.gz"
  echo "==> packaging ${TARBALL}"
  tar -C build -czf "$TARBALL" "${APP_NAME}.app"
fi

echo "==> done: $BUNDLE"
echo "    Launch the menu bar app via LaunchServices:  open $BUNDLE"
echo "    CLI use:  $BUNDLE/Contents/MacOS/worksync <command>"
