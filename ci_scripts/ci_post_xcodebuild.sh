#!/bin/sh
# Xcode Cloud runs this after archiving, before the build goes to TestFlight: a failure here stops it.
set -eu
cd "$CI_PRIMARY_REPOSITORY_PATH"
app="$CI_ARCHIVE_PATH/Products/Applications/iikb.app"
[ -d "$app" ] || { echo "no archive at $app" >&2; exit 1; }
for binary in "$app/iikb" "$app"/PlugIns/*.appex/*; do
  [ -f "$binary" ] && [ -x "$binary" ] || continue
  if strings -a "$binary" | grep -E '_UIKeyboardArbiterClient|LSApplicationWorkspace|LSApplicationProxy|TCCAccessPreflight|proc_pid_rusage|_hostProcessIdentifier'; then
    echo "$binary still names private API above; App Review would reject it" >&2
    exit 1
  fi
done

# What to Test is TestFlight/WhatToTest.en-US.txt, written for testers by hand when a beta is cut: a build without one
# stops here rather than show testers commit messages.
note=TestFlight/WhatToTest.en-US.txt
[ -s "$note" ] || { echo "$note is empty: write the testers' note" >&2; exit 1; }
git fetch --quiet --unshallow origin 2>/dev/null || true
git fetch --quiet --force origin 'refs/tags/beta-prev:refs/tags/beta-prev' 2>/dev/null || true
if git merge-base --is-ancestor beta-prev HEAD 2>/dev/null && git diff --quiet beta-prev HEAD -- "$note"; then
  echo "$note is the last beta's note: write this one's" >&2; exit 1
fi
cat "$note"
