# Runs the app on the Android emulator against the DEV backend (Firebase
# project little-blue-610e5 + the dev Shopify test shop) as a DEVELOPER build:
# the corner badge, the error strip with Copy for Claude and the Diagnostics
# row are on. The repo's client config is switched to dev for the run and
# back to prod when flutter exits, so nothing dev-shaped is left to commit.
#
# A plain `flutter run` (or scripts\run-prod.ps1) is the production app.
param([string]$Device = 'emulator-5554')
. "$PSScriptRoot\_common.ps1"
& "$PSScriptRoot\use-env.ps1" dev
if ($LASTEXITCODE -ne 0) { exit 1 }
Say "flutter run -d $Device --dart-define=LBM_DEV=true   (dev project)"
Write-Host "Tip: the corner badge in the app should read 'DEV · live · little-blue-610e5'. Press r to hot reload, q to quit."
Push-Location $Repo
try {
  flutter run -d $Device --dart-define=LBM_DEV=true
  $code = $LASTEXITCODE
} finally {
  Pop-Location
  & "$PSScriptRoot\use-env.ps1" prod | Out-Null
  Write-Host "Client config switched back to prod." -ForegroundColor DarkGray
}
if ($code -ne 0) { Fail "flutter run exited with $code. If it says 'No supported devices', start the Android emulator first (Android Studio -> Device Manager -> Play)." }
exit $code
