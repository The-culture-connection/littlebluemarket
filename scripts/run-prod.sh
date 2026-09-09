#!/usr/bin/env bash
# Git Bash wrapper for run-prod.ps1 (backslashes do not work as path separators in bash).
exec powershell -NoProfile -ExecutionPolicy Bypass -File "$(dirname "$0")/run-prod.ps1" "$@"
