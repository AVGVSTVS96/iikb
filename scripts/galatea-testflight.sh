#!/bin/bash
# One command from this checkout to TestFlight on the Galatea team (A95F4H2423).
#
#   scripts/galatea-testflight.sh            archive, export, upload, attach to the internal group
#   scripts/galatea-testflight.sh --archive  stop after a signed .xcarchive (no upload)
#
# The bundle ids are com.galateacorp.iikb{,.keyboard,.controls}: the Galatea team owns them
# because it cannot own com.shahidy.iikb, which is upstream's and already registered elsewhere.
# Everything else is upstream's build: ci_scripts/appstore.xcconfig compiles out the private API
# for App Store builds, and MARKETING_VERSION stays upstream's.
#
# Three host quirks are handled here, each measured on macOS 27 / Xcode 27.2:
#
# 1. xcodebuild sets CODE_SIGN_IDENTITY[sdk=iphoneos*] = "iPhone Developer" from the template, so
#    an archive asks Apple for a development certificate the keychain need not hold. The team is
#    named instead, which automatic signing resolves to the distribution certificate in it.
# 2. -exportArchive's IPA step shells /usr/bin/rsync, and macOS 27 ships openrsync, which rejects
#    the --extended-attributes the step passes ("Copy failed"). The export therefore runs with
#    /usr/bin first on PATH, where Xcode finds the same binary but no Homebrew rsync shadows it.
# 3. Xcode Cloud is upstream's beta lane. Nothing here needs -allowProvisioningUpdates to talk to
#    the App Store Connect API beyond the API key, so the key never has to be a person's login.
set -euo pipefail

cd "$(dirname "$0")/.."
TEAM=A95F4H2423
BUNDLE=com.galateacorp.iikb
GROUP=f5894ca9-8766-4c10-8bd6-fc37fe3d6515
ARCHIVE=build/iikb.xcarchive
KEY="${APP_STORE_CONNECT_API_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${APP_STORE_CONNECT_API_KEY_ID:?set APP_STORE_CONNECT_API_KEY_ID}.p8}"
ISSUER="${APP_STORE_CONNECT_API_ISSUER_ID:?set APP_STORE_CONNECT_API_ISSUER_ID}"
KEY_ID="${APP_STORE_CONNECT_API_KEY_ID:?set APP_STORE_CONNECT_API_KEY_ID}"

# A repeat build number is refused at upload, so every run takes the next one.
if [ "${1:-}" != "--archive" ]; then
  next=$(git log -1 --format=%cd --date=format:%Y%m%d%H%M)
  sed -i '' "s/^    CURRENT_PROJECT_VERSION: .*/    CURRENT_PROJECT_VERSION: \"$next\"/" project.yml
  echo "build number: $next"
fi

xcodegen generate -q

echo "archiving"
rm -rf "$ARCHIVE"
XCODE_XCCONFIG_FILE=$PWD/ci_scripts/appstore.xcconfig xcodebuild archive \
  -project iikb.xcodeproj -scheme iikb -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" -derivedDataPath build/dd \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="Apple Distribution" | grep -E "error:|ARCHIVE" || true
[ -d "$ARCHIVE" ] || { echo "no archive" >&2; exit 1; }

[ "${1:-}" = "--archive" ] && { echo "archive at $ARCHIVE"; exit 0; }

echo "exporting"
rm -rf build/export
cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>export</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$TEAM</string>
  <key>uploadSymbols</key><true/>
  <key>stripSwiftSymbols</key><true/>
</dict></plist>
PLIST
env PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportPath build/export -exportOptionsPlist build/ExportOptions.plist -allowProvisioningUpdates \
  | grep -E "error:|EXPORT" || true
[ -f build/export/iikb.ipa ] || { echo "no IPA" >&2; exit 1; }

echo "uploading"
xcrun altool --upload-app -f build/export/iikb.ipa -t ios \
  --apiKey "$KEY_ID" --apiIssuer "$ISSUER" 2>&1 | grep -E "UPLOAD SUCCEEDED|Delivery UUID|ERROR|error:" || true

# Not "done" until Apple says VALID and the build is on the internal group, so this waits for
# VALID and attaches it. A build a tester cannot see has shipped nothing.
echo "waiting for Apple to process $BUNDLE"
for i in $(seq 1 40); do
  sleep 30
  out=$("$PWD/scripts/asc-attach-build.py" "$BUNDLE" "$GROUP" 2>&1) && { echo "$out"; exit 0; }
  echo "  $out"
done
echo "still processing after 20 minutes; run scripts/asc-attach-build.py $BUNDLE $GROUP later" >&2
exit 1
