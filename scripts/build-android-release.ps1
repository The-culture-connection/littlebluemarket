# Builds the Android App Bundle (.aab) for the Google Play Console.
#
#   scripts\build-android-release.ps1
#
# Needs android\key.properties (copied from ..\android-signing\key.properties)
# and the keystore it names. Bumps nothing: set the version in pubspec.yaml
# first (version: X.Y.Z+N; N is the Play versionCode and must go up each
# upload). The bundle is copied to ..\android-signing\releases\ with the
# version in its name, and the upload certificate's fingerprints are printed
# for the Play Console (Setup -> App signing) if it ever asks.
. "$PSScriptRoot\_common.ps1"
$Parent = Split-Path $Repo -Parent
$signing = Join-Path $Parent "android-signing"
$props = Join-Path $Repo "android\key.properties"
if (-not (Test-Path $props)) {
  if (Test-Path (Join-Path $signing "key.properties")) {
    Copy-Item (Join-Path $signing "key.properties") $props -Force
    Say "android\key.properties restored from android-signing\"
  } else {
    Fail "No signing setup. Expected $signing\key.properties and upload-keystore.jks (see $signing\README.txt or README.md 'Android release')."
    exit 1
  }
}
$storeFile = (Select-String -Path $props -Pattern '^storeFile=(.+)$').Matches[0].Groups[1].Value
if (-not (Test-Path $storeFile)) { Fail "The keystore named in key.properties is missing: $storeFile"; exit 1 }

$version = (Select-String -Path (Join-Path $Repo "pubspec.yaml") -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value
Say "flutter build appbundle --release  (version $version)"
Push-Location $Repo
flutter build appbundle --release
$code = $LASTEXITCODE
Pop-Location
if ($code -ne 0) { Fail "the bundle did not build (above)."; exit 1 }

$aab = Join-Path $Repo "build\app\outputs\bundle\release\app-release.aab"
$out = Join-Path $signing "releases"
New-Item -ItemType Directory -Force $out | Out-Null
$dest = Join-Path $out ("little-blue-market-" + ($version -replace '\+', '-build') + ".aab")
Copy-Item $aab $dest -Force
Write-Host "`nBundle ready:" -ForegroundColor Green
Write-Host "  $dest"
Write-Host "Upload it at play.google.com/console -> Little Blue Market -> Production (or Testing) -> Create new release."

$keytool = "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe"
if (Test-Path $keytool) {
  $pw = (Select-String -Path $props -Pattern '^storePassword=(.+)$').Matches[0].Groups[1].Value
  $alias = (Select-String -Path $props -Pattern '^keyAlias=(.+)$').Matches[0].Groups[1].Value
  Write-Host "`nUpload certificate (for Play Console -> Setup -> App signing, if asked):"
  & $keytool -list -v -keystore $storeFile -alias $alias -storepass $pw 2>$null | Select-String "SHA1:|SHA256:" | ForEach-Object { "  " + $_.Line.Trim() }
}
