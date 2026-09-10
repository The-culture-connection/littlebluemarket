#!/usr/bin/env bash
# Run this on the Mac, in the project folder, BEFORE you archive in Xcode.
#
#   scripts/preflight-ios.sh
#
# It answers one question: will the archive I am about to make be the
# production app, with the newest fixes in it? It checks the four things that
# have actually gone wrong before, then resets Xcode's build settings from
# Flutter so the archive cannot inherit a leftover developer flag.
set -u
cd "$(dirname "$0")/.."

green=$'\033[32m'; red=$'\033[31m'; yellow=$'\033[33m'; off=$'\033[0m'
fails=0
pass() { printf '%sPASS%s  %s\n' "$green" "$off" "$1"; }
warn() { printf '%sWARN%s  %s\n' "$yellow" "$off" "$1"; }
fail() { printf '%sFAIL%s  %s\n   fix -> %s\n' "$red" "$off" "$1" "$2"; fails=$((fails + 1)); }

echo
echo "Preflight for an iPhone archive"
echo "-------------------------------"

# 1. The code is the code on GitHub.
git fetch -q origin main 2>/dev/null
local_head=$(git rev-parse HEAD)
remote_head=$(git rev-parse origin/main 2>/dev/null || echo unknown)
if [ -n "$(git status --porcelain)" ]; then
  fail "you have uncommitted changes, so this is not exactly what is on GitHub" \
       "git status  (then commit them, or 'git checkout -- <file>' to drop them)"
elif [ "$local_head" != "$remote_head" ]; then
  fail "this folder is not on the newest main" "git pull origin main"
else
  pass "on the newest main ($(git log -1 --format='%h %s' | cut -c1-64))"
fi

# 2. Firebase points at production, in all three places.
prod_ok=1
for pair in "lib/firebase_options.dart firebase/config/prod/firebase_options.dart" \
            "ios/Runner/GoogleService-Info.plist firebase/config/prod/GoogleService-Info.plist" \
            "android/app/google-services.json firebase/config/prod/google-services.json"; do
  set -- $pair
  cmp -s "$1" "$2" || prod_ok=0
done
project=$(grep -o "projectId: '[^']*'" lib/firebase_options.dart | head -1 | sed "s/.*'\(.*\)'/\1/")
if [ "$prod_ok" = "1" ]; then
  pass "Firebase project: $project (production)"
else
  fail "the app is pointed at $project, not the production project" \
       "scripts/use-env.sh prod"
fi

# 3. No developer flags left in Xcode's build settings. Xcode reuses whatever
#    the last 'flutter run' put here, which is how a Release build once came
#    out in dev mode.
xcconfig=ios/Flutter/Generated.xcconfig
if [ -f "$xcconfig" ] && grep -qE 'LBM_DEV|LBM_BACKEND' "$xcconfig"; then
  warn "Xcode still holds a developer flag from the last 'flutter run'; clearing it below"
fi

# 4. Refresh Xcode's settings from Flutter: version, build number and a clean
#    set of defines. This is the step that makes the archive production.
version=$(grep '^version:' pubspec.yaml | awk '{print $2}')
echo
echo "Resetting Xcode's build settings from Flutter (version $version)…"
if flutter build ios --config-only >/dev/null 2>&1; then
  pass "Xcode will build version ${version%+*}, build ${version#*+}"
else
  fail "'flutter build ios --config-only' did not finish" "run it on its own and read the error"
fi
if [ -f "$xcconfig" ] && grep -qE 'LBM_DEV|LBM_BACKEND' "$xcconfig"; then
  fail "a developer flag is still set, so the archive would be a dev build" \
       "close Xcode, run 'flutter build ios --config-only' again, then reopen"
else
  pass "no developer flags: the archive will be the production app"
fi

echo
if [ "$fails" -eq 0 ]; then
  printf '%sReady to archive.%s  Xcode -> Product -> Archive.\n\n' "$green" "$off"
else
  printf '%s%d thing(s) to fix first.%s\n\n' "$red" "$fails" "$off"
  exit 1
fi
