#!/usr/bin/env bash
# The Mac twin of run-live: a DEVELOPER build (corner badge, error strip with
# Copy for Claude) on a plugged-in iPhone. The Firebase project is whatever
# ios/Runner/GoogleService-Info.plist says: production unless
# `scripts/use-env.sh dev` was run first.
#
#   scripts/run-live-mac.sh                       # lists devices
#   scripts/run-live-mac.sh 00008110-0004…        # the phone's id (from `flutter devices`)
#
# The developer flag is written into ios/Flutter/Generated.xcconfig, and Xcode's
# own Run button reuses whatever is in that file. So when this script exits it
# regenerates the file without the flag: the next build from Xcode, or a plain
# `flutter run`, is the production app again.
set -euo pipefail
cd "$(dirname "$0")/.."

device="${1:-}"
if [ -z "$device" ]; then
  echo "Devices flutter can see:"
  flutter devices
  echo
  echo "Run again with the device id (or name) in quotes, e.g.:"
  echo "  scripts/run-live-mac.sh 00008110-000419860246201E"
  exit 2
fi

restore() {
  echo
  echo "Restoring the production build settings for Xcode and plain flutter run…"
  flutter build ios --config-only >/dev/null 2>&1 || true
}
trap restore EXIT

echo "flutter run -d \"$device\" --dart-define=LBM_DEV=true   (developer build)"
flutter run -d "$device" --dart-define=LBM_DEV=true
