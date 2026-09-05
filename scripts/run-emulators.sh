#!/usr/bin/env bash
# Git Bash wrapper for run-emulators.ps1 (backslashes do not work as path separators in bash).
exec powershell -NoProfile -ExecutionPolicy Bypass -File "$(dirname "$0")/run-emulators.ps1" "$@"
