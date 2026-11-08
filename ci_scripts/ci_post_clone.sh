#!/bin/sh
# Xcode Cloud runs this after cloning beta, the commit of main approved for TestFlight (main itself goes straight to
# the phone). Its workflow, set in App Store Connect, archives the iikb scheme with Xcode 27.1 and hands the build to
# TestFlight's Public group, the one behind the public link, which sends it to beta review. The workflow's
# XCODE_XCCONFIG_FILE points xcodebuild at appstore.xcconfig, which compiles in APP_STORE for every target, packages
# included; ci_post_xcodebuild.sh checks no private API is left and writes the What to Test note.
set -eu
cd "$CI_PRIMARY_REPOSITORY_PATH"
backup=Packages/KeyboardModules/Sources/KeyboardStore/Resources/Keys/backup.key
if [ -e "$backup" ]; then
  echo "$backup would send every tester's typing to its backup server" >&2
  exit 1
fi
printf %s "${KLIPY_KEY:?the workflow's secret KLIPY_KEY holds KLIPY's API key}" \
  >Packages/KeyboardModules/Sources/FullKeyboard/Resources/Keys/klipy.key
echo "DEVELOPMENT_TEAM = $CI_TEAM_ID" >Config/Team.xcconfig
brew install --quiet xcodegen
xcodegen generate -q
# Xcode Cloud resolves no packages itself: the generated project takes the pins of the root Package.resolved.
mkdir -p iikb.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
cp Package.resolved iikb.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/
