# Runs the PRODUCTION app on the Android emulator: Firebase project
# little-blue-cart-prod, the real shop, no developer surfaces. This is exactly
# what a plain `flutter run` does; the script only makes sure the client
# config is the prod one first (run-live puts it back itself, this is the
# belt and braces).
param([string]$Device = 'emulator-5554')
. "$PSScriptRoot\_common.ps1"
& "$PSScriptRoot\use-env.ps1" prod
if ($LASTEXITCODE -ne 0) { exit 1 }
Say "flutter run -d $Device   (PRODUCTION: little-blue-cart-prod, real shop)"
Push-Location $Repo
flutter run -d $Device
$code = $LASTEXITCODE
Pop-Location
if ($code -ne 0) { Fail "flutter run exited with $code. If it says 'No supported devices', start the Android emulator first (Android Studio -> Device Manager -> Play)." }
exit $code
