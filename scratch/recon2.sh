#!/bin/bash
set -uo pipefail
brew install --quiet blacktop/tap/ipsw >/dev/null 2>&1
RT=$(xcrun simctl list runtimes -j | /usr/bin/python3 -c "
import json,sys
rs=[r for r in json.load(sys.stdin)['runtimes'] if r['platform']=='iOS' and r['isAvailable'] and r['version']=='27.2']
print(rs[-1]['bundlePath'])")
R="$RT/Contents/Resources/RuntimeRoot"
C="$R/System/Library/Caches/com.apple.dyld/dyld_sim_shared_cache_arm64"
O=shots/raw/sounds; mkdir -p $O/bin $O/plist
ipsw dyld extract --help 2>&1 | head -40
for img in UIKitCore AudioToolbox AudioToolboxCore TextInputUI TextInputCore TextInput KeyboardServices UIKitServices; do
  ipsw dyld extract "$C" "$img" --objc --stubs -o $O/bin --force 2>&1 | tail -2 || ipsw dyld extract "$C" "$img" -o $O/bin 2>&1 | tail -2
done
ls -laR $O/bin | head -40
cp "$R/System/Library/Frameworks/AudioToolbox.framework/systemsoundserver-simd" $O/bin/
for p in PrivateFrameworks/KeyboardSettings.framework/Preferences_feedback.plist PreferenceBundles/KeyboardSettingsBundle.bundle/Preferences_feedback.plist PrivateFrameworks/Settings/SoundsAndHapticsSettings.framework/Sounds.plist LaunchDaemons/com.apple.audio.systemsoundserver-simd.plist; do
  echo "== $p"; plutil -p "$R/System/Library/$p" | head -200; plutil -convert xml1 -o "$O/plist/$(echo $p | tr / _)" "$R/System/Library/$p"
done
fd -H -t f -e plist . "$R/System/Library/Frameworks/AudioToolbox.framework" "$R/System/Library/PrivateFrameworks/AudioToolboxCore.framework" 2>/dev/null
cp -R "$R/System/Library/Frameworks/AudioToolbox.framework" $O/AudioToolbox.framework 2>/dev/null
afinfo "$R/System/Library/Audio/UISounds/key_press_click.caf"; for f in key_press_click key_press_delete key_press_modifier keyboard_press_normal keyboard_press_delete keyboard_press_clear Tock Tink; do echo "== $f"; afinfo "$R/System/Library/Audio/UISounds/$f.caf" | rg -i 'format|duration|channels'; md5 -q "$R/System/Library/Audio/UISounds/$f.caf"; cp "$R/System/Library/Audio/UISounds/$f.caf" $O/; done
fd -H 'key_press|keyboard_press' "$R" 2>/dev/null
du -sh $O
