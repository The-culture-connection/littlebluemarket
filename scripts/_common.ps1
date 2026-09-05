# Shared bits for the launchers. Dot-sourced; not meant to be run directly.
$ErrorActionPreference = 'Continue'
$Repo = Split-Path -Parent $PSScriptRoot
function Say($text)  { Write-Host "`n== $text ==" -ForegroundColor Cyan }
function Fail($text) { Write-Host "`nFAILED: $text" -ForegroundColor Red; Write-Host "Paste the last 30 lines of this window to Claude." -ForegroundColor Yellow }
