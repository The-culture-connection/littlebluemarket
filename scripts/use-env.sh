#!/usr/bin/env bash
# Points the APP at one Firebase project by copying that project's client
# config into place (the bash twin of use-env.ps1; works on a Mac and in Git
# Bash):
#   android/app/google-services.json, lib/firebase_options.dart and
#   ios/Runner/GoogleService-Info.plist   <-  firebase/config/<env>/
# The repo is committed as PROD (a plain `flutter run` is the production app).
#
#   scripts/use-env.sh prod
#   scripts/use-env.sh dev
set -euo pipefail
cd "$(dirname "$0")/.."

env="${1:-}"
if [ "$env" != "dev" ] && [ "$env" != "prod" ]; then
  echo "usage: scripts/use-env.sh dev|prod" >&2
  exit 2
fi
src="firebase/config/$env"
if [ ! -f "$src/google-services.json" ] || [ ! -f "$src/firebase_options.dart" ]; then
  echo "FAILED: $src is incomplete. Regenerate it: flutterfire configure --project=<project> --platforms=android,ios --out=lib/firebase_options.dart, then copy the files into $src/." >&2
  exit 1
fi
cp "$src/google-services.json" android/app/google-services.json
cp "$src/firebase_options.dart" lib/firebase_options.dart
if [ -f "$src/GoogleService-Info.plist" ]; then
  cp "$src/GoogleService-Info.plist" ios/Runner/GoogleService-Info.plist
fi
project="$(grep -m1 -o "projectId: '[^']*'" lib/firebase_options.dart | sed "s/projectId: '//; s/'//")"
echo "App now points at Firebase project: $project ($env)"
