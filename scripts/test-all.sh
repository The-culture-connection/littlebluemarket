#!/usr/bin/env bash
# Git Bash wrapper for test-all.ps1 (backslashes do not work as path separators in bash).
exec powershell -NoProfile -ExecutionPolicy Bypass -File "$(dirname "$0")/test-all.ps1" "$@"
