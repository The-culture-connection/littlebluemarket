# Runs the app with NO backend at all (built-in demo data). Good for looking at screens.
param([switch]$Chrome, [string]$Device = 'emulator-5554')
. "$PSScriptRoot\_common.ps1"
if ($Chrome) { $Device = 'chrome' }
Say "flutter run -d $Device --dart-define=LBM_BACKEND=fixtures --dart-define=LBM_DEV=true  (demo data, developer build)"
Push-Location $Repo
flutter run -d $Device --dart-define=LBM_BACKEND=fixtures --dart-define=LBM_DEV=true
$code = $LASTEXITCODE
Pop-Location
if ($code -ne 0) { Fail "flutter run exited with $code." }
exit $code
