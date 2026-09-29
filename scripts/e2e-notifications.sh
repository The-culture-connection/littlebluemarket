#!/usr/bin/env bash
# Git Bash twin of e2e-notifications.ps1. Pass --digest to wait for the forum digest.
cd "$(dirname "$0")/../functions" && exec node scripts/e2e-notifications.mjs "$@"
