#!/bin/bash
set -uo pipefail
RT=$(xcrun simctl list runtimes -j | /usr/bin/python3 -c "
import json,sys
rs=[r for r in json.load(sys.stdin)['runtimes'] if r['platform']=='iOS' and r['isAvailable']]
for r in rs: print(r['version'], r['bundlePath'], file=sys.stderr)
print(rs[-1]['bundlePath'])")
R="$RT/Contents/Resources/RuntimeRoot"
echo "ROOT $R"
echo "== UISounds"; ls -la "$R/System/Library/Audio/UISounds" | head -200
ls -la "$R/System/Library/Audio/UISounds/"*/ 2>/dev/null | rg -i 'key|click|tock|tink' 
echo "== caches"; fd -t f -H 'dyld' "$R/System/Library" -d 3 2>/dev/null | head; ls -la "$R/System/Library/Caches/com.apple.dyld" 2>/dev/null
for fw in PrivateFrameworks/UIKitCore PrivateFrameworks/TextInputUI PrivateFrameworks/TextInputCore PrivateFrameworks/KeyboardServices Frameworks/AudioToolbox PrivateFrameworks/AudioToolboxCore PrivateFrameworks/UIKitServices PrivateFrameworks/TextInput; do
  n=${fw##*/}; f="$R/System/Library/$fw.framework/$n"; echo "== $fw"; ls -la "$f" 2>&1
done
echo "== files naming sound prefs"
rg -a -l 'com\.apple\.preferences\.sounds' "$R/System/Library" "$R/usr" 2>/dev/null | head -40
echo "== UISounds plist / ids"
fd -H -i 'systemsound|soundid|UISounds' "$R/System/Library" 2>/dev/null | head -30
brew install --quiet blacktop/tap/ipsw >/dev/null 2>&1 && ipsw version
