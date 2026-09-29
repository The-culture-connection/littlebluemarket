# scripts\e2e-notifications.ps1 [-Digest]
# Proves the notification rules on the DEV project with a real FCM device:
# a push only counts when Google's push service delivers it to this machine.
# About 6 minutes; -Digest also waits for the scheduled forum digest (~35 min).
# Dev only; the two throwaway accounts it makes are deleted at the end.
param([switch]$Digest)
$Repo = Split-Path $PSScriptRoot -Parent
Push-Location (Join-Path $Repo 'functions')
if ($Digest) { node scripts/e2e-notifications.mjs --digest } else { node scripts/e2e-notifications.mjs }
$code = $LASTEXITCODE
Pop-Location
exit $code
