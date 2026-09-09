# Runs the app on the Android emulator as a DEVELOPER build: the corner badge,
# the error strip with Copy for Claude and the Diagnostics row are on.
#
# Since the production cutover (Grace, 2026-09-09) this targets PRODUCTION
# (Firebase project little-blue-cart-prod, the real shop): the same data the
# customer app sees, plus the developer surfaces. The badge reads
# 'DEV · live · little-blue-cart-prod'.
#
#   scripts\run-live.ps1          # developer build against production
#   scripts\run-live.ps1 -Dev     # developer build against the DEV project
#                                 # (little-blue-610e5 + the test shop); the
#                                 # client config is swapped for the run and
#                                 # put back when flutter exits
#
# A plain `flutter run` (or scripts\run-prod.ps1) is the production app with
# no developer surfaces.
param([string]$Device = 'emulator-5554', [switch]$Dev)
. "$PSScriptRoot\_common.ps1"
$target = if ($Dev) { 'dev' } else { 'prod' }
& "$PSScriptRoot\use-env.ps1" $target
if ($LASTEXITCODE -ne 0) { exit 1 }
$label = if ($Dev) { 'DEV project little-blue-610e5' } else { 'PRODUCTION little-blue-cart-prod' }
Say "flutter run -d $Device --dart-define=LBM_DEV=true   ($label, developer surfaces on)"
Write-Host "Tip: the corner badge should read 'DEV · live · $(if ($Dev) { 'little-blue-610e5' } else { 'little-blue-cart-prod' })'. Press r to hot reload, q to quit."
Push-Location $Repo
try {
  flutter run -d $Device --dart-define=LBM_DEV=true
  $code = $LASTEXITCODE
} finally {
  Pop-Location
  if ($Dev) {
    & "$PSScriptRoot\use-env.ps1" prod | Out-Null
    Write-Host "Client config switched back to prod." -ForegroundColor DarkGray
  }
}
if ($code -ne 0) { Fail "flutter run exited with $code. If it says 'No supported devices', start the Android emulator first (Android Studio -> Device Manager -> Play)." }
exit $code
