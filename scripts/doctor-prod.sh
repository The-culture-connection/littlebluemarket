#!/usr/bin/env bash
# Git Bash wrapper for doctor-prod.ps1 (backslashes do not work as path separators in bash).
exec powershell -NoProfile -ExecutionPolicy Bypass -File "$(dirname "$0")/doctor-prod.ps1" "$@"
