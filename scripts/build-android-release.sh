#!/usr/bin/env bash
# Git Bash wrapper for build-android-release.ps1.
exec powershell -NoProfile -ExecutionPolicy Bypass -File "$(dirname "$0")/build-android-release.ps1" "$@"
