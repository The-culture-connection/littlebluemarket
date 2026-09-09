# Points the APP at one Firebase project by copying that project's client
# config into place:
#   android\app\google-services.json   and   lib\firebase_options.dart
# from firebase\config\<env>\. The repo is committed as PROD (a plain
# `flutter run` is the production app); `use-env dev` is for a dev session and
# run-live switches back to prod when it exits.
#
#   scripts\use-env.ps1 prod
#   scripts\use-env.ps1 dev
param([Parameter(Mandatory = $true)][ValidateSet('dev', 'prod')][string]$Env)
. "$PSScriptRoot\_common.ps1"
$src = Join-Path $Repo "firebase\config\$Env"
if (-not (Test-Path "$src\google-services.json") -or -not (Test-Path "$src\firebase_options.dart")) {
  Fail "firebase\config\$Env is incomplete. Regenerate it: flutterfire configure --project=<project> --platforms=android,ios --out=lib/firebase_options.dart, then copy the two files into firebase\config\$Env\."
  exit 1
}
Copy-Item "$src\google-services.json" (Join-Path $Repo "android\app\google-services.json") -Force
Copy-Item "$src\firebase_options.dart" (Join-Path $Repo "lib\firebase_options.dart") -Force
if (Test-Path "$src\GoogleService-Info.plist") {
  Copy-Item "$src\GoogleService-Info.plist" (Join-Path $Repo "ios\Runner\GoogleService-Info.plist") -Force
}
$project = (Select-String -Path (Join-Path $Repo "lib\firebase_options.dart") -Pattern "projectId: '([^']+)'" | Select-Object -First 1).Matches[0].Groups[1].Value
Write-Host "App now points at Firebase project: $project ($Env)" -ForegroundColor Green
