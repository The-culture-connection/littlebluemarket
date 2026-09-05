# Runs the app on the Android emulator against the REAL dev backend
# (Firebase project little-blue-610e5 + the dev Shopify test shop). Your default.
param([string]$Device = 'emulator-5554')
. "$PSScriptRoot\_common.ps1"
Say "flutter run -d $Device --dart-define=LBM_BACKEND=live"
Write-Host "Tip: the corner badge in the app should read 'DEV · live · little-blue-610e5'. Press r to hot reload, q to quit."
Push-Location $Repo
flutter run -d $Device --dart-define=LBM_BACKEND=live
$code = $LASTEXITCODE
Pop-Location
if ($code -ne 0) { Fail "flutter run exited with $code. If it says 'No supported devices', start the Android emulator first (Android Studio -> Device Manager -> Play)." }
exit $code
