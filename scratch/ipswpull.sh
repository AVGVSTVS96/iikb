#!/bin/bash
# scratch/ipswpull.sh: Apple's keyboard haptic pattern library and its audio, from the iOS 27.2.1 IPSWs.
set -uo pipefail
cd "$(dirname "$0")/.."
brew install --quiet blacktop/tap/ipsw >/dev/null 2>&1 || brew install blacktop/tap/ipsw
ipsw version | head -2
df -h . | tail -1
PAT='(Library/Audio/Tunings/.*/Haptics/|System/Library/Audio/UISounds/|System/Library/Audio/Tunings/.*/Haptics/|Library/Audio/Tunings/[^/]+/[^/]*\.plist$)'
O=$PWD/shots/raw/ipsw; mkdir -p $O
W=$HOME/ipswwork; mkdir -p $W
for pair in "iPhone19,4 https://updates.cdn-apple.com/2026FallFCS/a553d457-a2b6-4b9d-86f9-2f9d67631fd6/iPhone19,4_27.2.1_24B91034_Restore.ipsw" \
            "iPhone17,2 https://updates.cdn-apple.com/2026FallFCS/174fcce0-6d12-4bae-a2c3-9fd2e13d6dff/iPhone17,2_27.2.1_24B156_Restore.ipsw"; do
  set -- $pair; dev=$1; url=$2
  echo "=== $dev"
  mkdir -p $O/$dev
  if ! perl -e 'alarm 2400; exec @ARGV' ipsw extract --files --pattern "$PAT" --remote -o $O/$dev "$url" 2>&1 | tail -15; then echo "remote failed"; fi
  n=$(fd -t f . $O/$dev | wc -l)
  echo "remote got $n files"
  if [ "$n" -lt 3 ]; then
    (cd $W && perl -e 'alarm 3000; exec @ARGV' curl -sSfLO "$url") || { echo "download failed"; continue; }
    f=$W/$(basename "$url"); ls -la "$f"; df -h . | tail -1
    perl -e 'alarm 2400; exec @ARGV' ipsw extract --files --pattern "$PAT" -o $O/$dev "$f" 2>&1 | tail -15
    rm -f "$f"
  fi
  fd -t f . $O/$dev | rg -i 'haptic|key|tunings' | head -80
  fd -t f . $O/$dev | wc -l
done
for p in $(fd -t f 'hapticpatternlibrary' $O); do
  echo "##### $p"
  plutil -convert xml1 -o - "$p" > "$p.xml"
  rg -n -i 'keyboard' "$p.xml" | head -40
done
du -sh $O
