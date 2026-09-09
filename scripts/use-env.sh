#!/usr/bin/env bash
# Git Bash wrapper for use-env.ps1 (backslashes do not work as path separators in bash).
exec powershell -NoProfile -ExecutionPolicy Bypass -File "$(dirname "$0")/use-env.ps1" "$@"
