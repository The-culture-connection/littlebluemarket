# Runs the app against LOCAL Firebase emulators with seeded demo data.
# Opens the emulator suite in a second window, seeds it, then starts the app.
param([string]$Device = 'emulator-5554')
. "$PSScriptRoot\_common.ps1"
Say "Starting the Firebase emulators in a new window"
Start-Process powershell -ArgumentList "-NoExit", "-Command", "Set-Location '$Repo'; firebase emulators:start --only firestore,auth,functions,storage"
Write-Host "Waiting for Firestore emulator on port 8080..."
$tries = 0
while ($tries -lt 60) {
  try { $c = New-Object Net.Sockets.TcpClient('127.0.0.1', 8080); $c.Close(); break } catch { Start-Sleep 1; $tries++ }
}
if ($tries -ge 60) { Fail "the Firestore emulator never answered on 8080. Look at the emulator window."; exit 1 }
Say "Seeding demo content"
Push-Location "$Repo\functions"
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080'
$env:GCLOUD_PROJECT = 'little-blue-610e5'
npm run seed
Pop-Location
Say "flutter run -d $Device --dart-define=LBM_BACKEND=live --dart-define=LBM_EMULATORS=true"
Push-Location $Repo
flutter run -d $Device --dart-define=LBM_BACKEND=live --dart-define=LBM_EMULATORS=true
Pop-Location
