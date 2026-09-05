#!/usr/bin/env bash
exec powershell -NoProfile -ExecutionPolicy Bypass -File "$(dirname "$0")/probe-shipturtle.ps1" "$@"
