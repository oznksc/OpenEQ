#!/usr/bin/env bash
# Build a Release OpenEQ.app and package dist/OpenEQ-<version>.dmg
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT="OpenEQ.xcodeproj"
SCHEME="OpenEQ"
CONFIGURATION="Release"
DERIVED="${ROOT}/build/DerivedData"
STAGE="${ROOT}/build/dmg-stage"
DIST="${ROOT}/dist"

VERSION="$(grep -m1 'MARKETING_VERSION =' OpenEQ.xcodeproj/project.pbxproj | sed -E 's/.*MARKETING_VERSION = ([^;]+);/\1/' | tr -d ' ')"
VERSION="${VERSION:-1.0.0}"
DMG_NAME="OpenEQ-${VERSION}.dmg"
VOL_NAME="OpenEQ ${VERSION}"

echo "==> Building ${SCHEME} (${CONFIGURATION}), version ${VERSION}"
rm -rf "${DERIVED}" "${STAGE}"
mkdir -p "${DERIVED}" "${STAGE}" "${DIST}"

xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -derivedDataPath "${DERIVED}" \
  -destination 'platform=macOS' \
  build

APP="$(find "${DERIVED}/Build/Products/${CONFIGURATION}" -name 'OpenEQ.app' -type d | head -n 1)"
if [[ -z "${APP}" || ! -d "${APP}" ]]; then
  echo "error: OpenEQ.app not found under ${DERIVED}" >&2
  exit 1
fi

echo "==> Staging ${APP}"
ditto "${APP}" "${STAGE}/OpenEQ.app"
ln -sf /Applications "${STAGE}/Applications"

echo "==> Creating ${DIST}/${DMG_NAME}"
rm -f "${DIST}/${DMG_NAME}"
hdiutil create \
  -volname "${VOL_NAME}" \
  -srcfolder "${STAGE}" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "${DIST}/${DMG_NAME}"

echo "==> Done: ${DIST}/${DMG_NAME}"
ls -lh "${DIST}/${DMG_NAME}"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${STAGE}/OpenEQ.app/Contents/Info.plist" || true
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${STAGE}/OpenEQ.app/Contents/Info.plist" || true
