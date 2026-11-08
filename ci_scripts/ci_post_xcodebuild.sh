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

# What to Test: the commits since the last beta, which .github/workflows/beta.yml tags beta-prev on every move of beta.
git fetch --quiet --unshallow origin 2>/dev/null || true
git fetch --quiet --force origin 'refs/tags/beta-prev:refs/tags/beta-prev' 2>/dev/null || true
range=HEAD~1..HEAD
git merge-base --is-ancestor beta-prev HEAD 2>/dev/null && range=beta-prev..HEAD
mkdir -p TestFlight
git log --no-merges --format='- %s' "$range" | sed -E 's/^- [a-z]+(\([^)]*\))?!?: /- /' | head -20 \
  >TestFlight/WhatToTest.en-US.txt
cat TestFlight/WhatToTest.en-US.txt
