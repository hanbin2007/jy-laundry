#!/usr/bin/env bash
# Archive the app, sign it for App Store Connect and upload it to TestFlight.
# Used by .github/workflows/testflight.yml and runnable on a Mac by hand.
#
# Needs: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (App Store Connect API key).
# The version (MARKETING_VERSION) always comes from the Xcode project; each
# upload only gets a new build number.
# Optional:
#   BUILD_NUMBER       override the build number (default: highest uploaded + 1)
#   WHATS_NEW_FILE     text file for TestFlight "What to Test"
#   PUBLIC_BETA_GROUP  external group with the public link (default "Public Beta";
#                      empty to skip the public beta)
#   EXPORT_ONLY=1      sign and export an .ipa locally instead of uploading
set -euo pipefail

: "${ASC_KEY_ID:?}" "${ASC_ISSUER_ID:?}" "${ASC_KEY_PATH:?}"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# Server settings go into the gitignored Config/Secrets.xcconfig (never on the
# xcodebuild command line, which would print them into the build log).
SECRETS="$ROOT/Config/Secrets.xcconfig"
if [[ -n "${LAUNDRY_SERVER_URL:-}" && -n "${LAUNDRY_SERVER_TOKEN:-}" ]]; then
  # "//" starts a comment in xcconfig files; "/$()/" is the usual escape.
  escaped_url="${LAUNDRY_SERVER_URL//\/\//\/\$()\/}"
  printf 'LAUNDRY_SERVER_URL = %s\nLAUNDRY_SERVER_TOKEN = %s\n' "$escaped_url" "$LAUNDRY_SERVER_TOKEN" > "$SECRETS"
fi
if ! grep -Eq '^LAUNDRY_SERVER_TOKEN *= *[^ ]' "$SECRETS" 2>/dev/null; then
  echo "No server settings: set LAUNDRY_SERVER_URL and LAUNDRY_SERVER_TOKEN, or fill in Config/Secrets.xcconfig." >&2
  exit 1
fi

PROJECT=Laundry.xcodeproj
SCHEME=Laundry
BUNDLE_ID=com.zhanghanbin.laundry
OUT="${OUT_DIR:-$ROOT/build}"
ARCHIVE="$OUT/Laundry.xcarchive"
ASC="python3 $ROOT/scripts/ci/asc.py"

AUTH=(-allowProvisioningUpdates
      -authenticationKeyPath "$ASC_KEY_PATH"
      -authenticationKeyID "$ASC_KEY_ID"
      -authenticationKeyIssuerID "$ASC_ISSUER_ID")

MARKETING_VERSION="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -showBuildSettings 2>/dev/null | awk -F' = ' '/ MARKETING_VERSION = /{print $2; exit}')"
if [[ -z "${BUILD_NUMBER:-}" ]]; then
  BUILD_NUMBER="$($ASC next-build-number "$BUNDLE_ID")"
fi
echo "==> Building $BUNDLE_ID $MARKETING_VERSION ($BUILD_NUMBER)"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  { echo "version=$MARKETING_VERSION"; echo "build=$BUILD_NUMBER"; } >> "$GITHUB_OUTPUT"
fi

rm -rf "$ARCHIVE" "$OUT/export"
mkdir -p "$OUT"

# Run xcodebuild with its full log in a file; show errors and the tail on failure.
run_logged() {
  local log="$1"; shift
  if "$@" > "$log" 2>&1; then
    grep -E "^\*\* .* SUCCEEDED \*\*|Uploaded|Upload succeeded" "$log" || true
  else
    grep -E "error:|^\*\* .* FAILED \*\*" "$log" | head -40 || true
    echo "---- last 60 lines of $log ----"; tail -60 "$log"
    exit 1
  fi
}

# The archive is built unsigned; -exportArchive signs it for distribution with a
# cloud-managed certificate, so no certificate or keychain is needed on the runner.
echo "==> Archiving"
run_logged "$OUT/archive.log" xcodebuild archive \
  -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGNING_ALLOWED=NO

OPTIONS="$ROOT/scripts/ci/ExportOptions.plist"
if [[ "${EXPORT_ONLY:-0}" == "1" ]]; then
  OPTIONS="$OUT/ExportOptions-local.plist"
  cp "$ROOT/scripts/ci/ExportOptions.plist" "$OPTIONS"
  /usr/libexec/PlistBuddy -c "Set :destination export" "$OPTIONS"
fi

echo "==> Signing and $( [[ "${EXPORT_ONLY:-0}" == "1" ]] && echo exporting || echo uploading )"
run_logged "$OUT/export.log" xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$OPTIONS" \
  -exportPath "$OUT/export" \
  "${AUTH[@]}"

[[ "${EXPORT_ONLY:-0}" == "1" ]] && { echo "==> Exported to $OUT/export"; exit 0; }

echo "==> Waiting for App Store Connect to process the build"
BUILD_ID="$($ASC wait-build "$BUNDLE_ID" "$MARKETING_VERSION" "$BUILD_NUMBER")"
if [[ -n "${WHATS_NEW_FILE:-}" && -s "$WHATS_NEW_FILE" ]]; then
  $ASC set-whats-new "$BUILD_ID" "$WHATS_NEW_FILE" en-US
fi
$ASC ensure-group "$BUNDLE_ID" "Internal" >/dev/null

# Public beta: the external group with the public link gets every build. Apple
# reviews the first build of each version; later builds of the same version
# are usually approved automatically.
PUBLIC_GROUP="${PUBLIC_BETA_GROUP-Public Beta}"
if [[ -n "$PUBLIC_GROUP" ]]; then
  echo "==> Public beta ($PUBLIC_GROUP)"
  PUBLIC_LINK="$($ASC ensure-public-group "$BUNDLE_ID" "$PUBLIC_GROUP")"
  $ASC add-to-group "$BUILD_ID" "$PUBLIC_GROUP"
  $ASC submit-beta-review "$BUILD_ID"
  echo "Public link: $PUBLIC_LINK"
  [[ -n "${GITHUB_OUTPUT:-}" ]] && echo "public_link=$PUBLIC_LINK" >> "$GITHUB_OUTPUT"
fi
echo "==> $MARKETING_VERSION ($BUILD_NUMBER) is on TestFlight"
