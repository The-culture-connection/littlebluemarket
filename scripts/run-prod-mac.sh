#!/usr/bin/env bash
# The PRODUCTION app on a plugged-in iPhone: little-blue-cart-prod, the real
# shop, no developer surfaces. Exactly what a plain `flutter run` does; this
# only makes sure the production client config is in place first and prints
# the device list when no device is given.
#
#   scripts/run-prod-mac.sh 00008110-0004…        # the phone's id (from `flutter devices`)
set -euo pipefail
cd "$(dirname "$0")/.."

device="${1:-}"
if [ -z "$device" ]; then
  echo "Devices flutter can see:"
  flutter devices
  echo
  echo "Run again with the device id (or name) in quotes, e.g.:"
  echo "  scripts/run-prod-mac.sh 00008110-000419860246201E"
  exit 2
fi

scripts/use-env.sh prod >/dev/null 2>&1 || true
echo "flutter run -d \"$device\"   (PRODUCTION: little-blue-cart-prod, real shop)"
exec flutter run -d "$device"
