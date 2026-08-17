#!/bin/bash
# build-app.sh — release build + WorkSync.app assembly + codesign + tarball.
#
# Usage:
#   scripts/build-app.sh [--identity "IDENTITY"] [--adhoc] [--no-tar] [--notarize]
#
# --notarize submits to Apple and staples the ticket into the bundle. Needs a
# Developer ID identity and AC_API_KEY_PATH / AC_API_KEY_ID / AC_API_ISSUER_ID.
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
NOTARIZE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --identity) IDENTITY="$2"; shift 2 ;;
    --adhoc)    ADHOC=1; shift ;;
    --no-tar)   MAKE_TAR=0; shift ;;
    --notarize) NOTARIZE=1; shift ;;
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

# The version lives in two files and CI only checks the plist against the tag,
# so a bump that misses the Swift constant ships a binary whose --version
# disagrees with the bundle it is inside — and nothing downstream notices.
PLIST_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
SOURCE_VERSION=$(sed -n 's/^let worksyncVersion = "\(.*\)"$/\1/p' Sources/worksync/WorkSync.swift)
if [[ "$PLIST_VERSION" != "$SOURCE_VERSION" ]]; then
  echo "error: version mismatch — Info.plist says $PLIST_VERSION, WorkSync.swift says $SOURCE_VERSION" >&2
  echo "       bump both before building a release." >&2
  exit 1
fi

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

# SwiftPM stamps LC_BUILD_VERSION's `sdk` field with the DEPLOYMENT TARGET
# rather than the SDK it actually compiled against. macOS gates modern control
# appearance on that field, so without this restamp the UI silently renders
# legacy Aqua controls — no error, nothing to debug (SPEC §3.1 rule 6).
# Must run BEFORE codesign: restamping afterwards invalidates the signature.
SDK_VERSION=$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || echo "")
MIN_VERSION=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" Resources/Info.plist 2>/dev/null || echo "14.0")
if [[ -n "$SDK_VERSION" ]] && command -v vtool >/dev/null 2>&1; then
  echo "==> restamping SDK version ($MIN_VERSION -> built against $SDK_VERSION)"
  APP_BINARY="$BUNDLE/Contents/MacOS/worksync"
  if vtool -set-build-version macos "$MIN_VERSION" "$SDK_VERSION" -replace \
      -output "$APP_BINARY.tmp" "$APP_BINARY" 2>/dev/null; then
    mv "$APP_BINARY.tmp" "$APP_BINARY"
  else
    rm -f "$APP_BINARY.tmp"
    echo "    warning: vtool restamp failed; modern controls may fall back to legacy Aqua" >&2
  fi
else
  echo "    warning: vtool or SDK version unavailable; skipping SDK restamp" >&2
fi

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

if [[ "$NOTARIZE" -eq 1 ]]; then
  if [[ "$ADHOC" -eq 1 ]]; then
    echo "ERROR: --notarize needs a Developer ID identity; ad-hoc cannot be notarized." >&2
    exit 1
  fi
  : "${AC_API_KEY_PATH:?--notarize needs AC_API_KEY_PATH (App Store Connect .p8)}"
  : "${AC_API_KEY_ID:?--notarize needs AC_API_KEY_ID}"
  : "${AC_API_ISSUER_ID:?--notarize needs AC_API_ISSUER_ID}"

  # notarytool accepts only .zip, .pkg and .dmg — verified by running it
  # against a .tar.gz, which it refuses at pre-flight. The zip is a transport
  # for the notary service only; it is never published.
  ZIP="build/${APP_NAME}-notarize.zip"
  echo "==> zipping for notarization"
  rm -f "$ZIP"
  # ditto, not zip(1): ditto preserves the bundle's symlinks and extended
  # attributes, and a plain zip can produce an archive the notary rejects.
  ditto -c -k --keepParent "$BUNDLE" "$ZIP"

  echo "==> notarytool submit (waits for Apple; usually 1-5 min)"
  xcrun notarytool submit "$ZIP" \
    --key "$AC_API_KEY_PATH" \
    --key-id "$AC_API_KEY_ID" \
    --issuer "$AC_API_ISSUER_ID" \
    --wait
  rm -f "$ZIP"

  # Staple the BUNDLE, not the zip: the ticket has to travel inside the .app so
  # Gatekeeper can validate with no network. Without stapling, a first launch
  # offline fails even though the app is notarized.
  echo "==> stapling"
  xcrun stapler staple "$BUNDLE"
  xcrun stapler validate "$BUNDLE"

  # The verdict users actually get. Checked here so a broken release fails the
  # build rather than shipping and failing on their machine.
  echo "==> Gatekeeper assessment"
  if ! spctl -a -vvv -t exec "$BUNDLE" 2>&1 | tee /dev/stderr | grep -q "source=Notarized Developer ID"; then
    echo "ERROR: Gatekeeper did not accept the notarized bundle." >&2
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

  # A second, version-less copy so a `releases/latest/download/...` URL can be
  # written down once and keep working. Without it the only published name
  # contains the version, and any documented download link 404s the moment a
  # new tag ships.
  STABLE="build/${APP_NAME}-${ARCH}.tar.gz"
  cp "$TARBALL" "$STABLE"
  echo "==> stable alias ${STABLE}"
fi

echo "==> done: $BUNDLE"
echo
echo "Launch the menu bar app:  open $BUNDLE"
echo
echo "To use the CLI as \`worksync\`, put it on your PATH:"
echo "    mkdir -p ~/.local/bin"
echo "    ln -sf \"$(cd "$(dirname "$BUNDLE")" && pwd)/$(basename "$BUNDLE")/Contents/MacOS/worksync\" ~/.local/bin/worksync"
echo "    # then ensure ~/.local/bin is on PATH"
