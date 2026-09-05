# Runs the app with NO backend at all (built-in demo data). Good for looking at screens.
param([switch]$Chrome, [string]$Device = 'emulator-5554')
. "$PSScriptRoot\_common.ps1"
if ($Chrome) { $Device = 'chrome' }
Say "flutter run -d $Device  (fixtures backend)"
Push-Location $Repo
flutter run -d $Device
$code = $LASTEXITCODE
Pop-Location
if ($code -ne 0) { Fail "flutter run exited with $code." }
exit $code
