#!/usr/bin/env bash
# The Mac twin of run-live: runs the app on a plugged-in iPhone (or the iOS
# Simulator) against the REAL dev backend. No PowerShell on a Mac, so this one
# is plain bash.
#
#   scripts/run-live-mac.sh              # picks the one connected iPhone, or asks
#   scripts/run-live-mac.sh "Grace's iPhone"
#
# The corner badge in the app should read 'DEV · live · little-blue-610e5'.
# Press r to hot reload, q to quit. Push needs a real iPhone, not the Simulator.
set -euo pipefail
cd "$(dirname "$0")/.."

device="${1:-}"
if [ -z "$device" ]; then
  echo "Devices flutter can see:"
  flutter devices
  echo
  echo "Run again with the device name or id in quotes, e.g.:"
  echo "  scripts/run-live-mac.sh \"Grace's iPhone\""
  exit 2
fi

echo "flutter run -d \"$device\" --dart-define=LBM_BACKEND=live"
exec flutter run -d "$device" --dart-define=LBM_BACKEND=live
