#!/bin/bash
# scratch/keysounds.sh <config>...: configs system-on system-off iikb iikb-full
set -uo pipefail
cd "$(dirname "$0")/.."
O=shots/raw/sounds; mkdir -p $O
ID=$(scripts/sim ensure "iPhone Duo" iPhone-Duo)
xcrun -sdk iphonesimulator clang -arch arm64 -mios-simulator-version-min=27.0 -dynamiclib -fobjc-arc -O1 \
  -framework Foundation -framework AudioToolbox -framework CoreHaptics -framework CoreGraphics -Wl,-U,_AudioServicesPlaySystemSoundWithOptions \
  -Wl,-U,_AudioServicesPlaySystemSoundWithVibration -o build/sndtrace.dylib scratch/soundtrace.m || exit 1
codesign -f -s - build/sndtrace.dylib
xcodegen generate -q
xcodebuild build-for-testing -project iikb.xcodeproj -scheme iikb -destination "id=$ID" -derivedDataPath build/uitest -quiet 2>&1 | rg -v '^\s*$' | tail -5
export APP=$PWD/build/uitest/Build/Products/Debug-iphonesimulator/iikb.app
ls -d "$APP" || exit 1
scripts/sim boot "$ID"
PREFKEY=${PREFKEY:-keyboard-audio}
for cfg in "$@"; do
  echo "=== $cfg"
  case $cfg in
    system-*) xcrun simctl spawn "$ID" defaults write .GlobalPreferences AppleKeyboards -array "en_US@sw=QWERTY;hw=Automatic" "emoji@sw=Emoji" "fr_FR@sw=AZERTY;hw=Automatic" ;;
    iikb*) xcrun simctl spawn "$ID" defaults write .GlobalPreferences AppleKeyboards -array "com.shahidy.iikb.keyboard" "en_US@sw=QWERTY;hw=Automatic" "emoji@sw=Emoji" ;;
  esac
  xcrun simctl spawn "$ID" defaults write .GlobalPreferences AppleKeyboardsExpanded -int 1
  for k in KeyboardAutocorrection KeyboardAutocapitalization; do xcrun simctl spawn "$ID" defaults write com.apple.Preferences $k -bool NO; done
  case $cfg in
    *-off) xcrun simctl spawn "$ID" defaults write com.apple.preferences.sounds "$PREFKEY" -bool NO ;;
    *-on) xcrun simctl spawn "$ID" defaults write com.apple.preferences.sounds "$PREFKEY" -bool YES ;;
    *) xcrun simctl spawn "$ID" defaults delete com.apple.preferences.sounds "$PREFKEY" 2>/dev/null ;;
  esac
  echo "prefs sounds:"; xcrun simctl spawn "$ID" defaults read com.apple.preferences.sounds 2>&1 | head -30
  scripts/sim down "$ID"; scripts/sim boot "$ID" >/dev/null
  [[ $cfg == iikb-full* ]] && scripts/sim allow "$ID"
  xcrun simctl install "$ID" "$APP"
  xcrun simctl spawn "$ID" log config --mode "level:debug,persist:debug" 2>&1 | head -2
  xcrun simctl spawn "$ID" launchctl setenv SNDTRACE_HOOKS "${HOOKS:-}"
  xcrun simctl spawn "$ID" launchctl kill TERM system/com.apple.audio.systemsoundserver-simd 2>/dev/null
  xcrun simctl spawn "$ID" launchctl list | rg -i 'sound' | head -5
  rm -f /tmp/sndtrace.log; touch /tmp/sndtrace.log; chmod 666 /tmp/sndtrace.log
  start=$(date '+%Y-%m-%d %H:%M:%S')
  TEST_RUNNER_SNDTRACE_DYLIB=$([[ $cfg == iikb* ]] || echo "$PWD/build/sndtrace.dylib") TEST_RUNNER_SNDTRACE_IIKB=$([[ $cfg == iikb* ]] && echo 1 || echo 0) perl -e "alarm 1200; exec @ARGV" xcodebuild test-without-building -collect-test-diagnostics never \
    -project iikb.xcodeproj -scheme iikb -destination "id=$ID" -derivedDataPath build/uitest \
    -only-testing:AppUITests/KeySounds > $O/$cfg.xcodebuild.txt 2>&1
  rg -e 'error:|failed|Executed|XCTAssert' $O/$cfg.xcodebuild.txt | head -10
  cp /tmp/sndtrace.log $O/$cfg.trace; wc -l $O/$cfg.trace
  xcrun simctl spawn "$ID" log show --start "$start" --info --debug --style compact \
    --predicate 'eventMessage CONTAINS "SNDTRACE" OR eventMessage CONTAINS "SNDMARK" OR process BEGINSWITH "systemsoundserver" OR (process == "iikb" AND eventMessage CONTAINS[c] "feedback")' > $O/$cfg.log 2>&1
  wc -l $O/$cfg.log
  rg -c 'SNDTRACE' $O/$cfg.log
  xcrun simctl spawn "$ID" launchctl unsetenv DYLD_INSERT_LIBRARIES
done
