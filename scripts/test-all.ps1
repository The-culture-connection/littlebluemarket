# Every automated gate, stopping at the first failure:
#   flutter analyze -> flutter test -> tsc --noEmit -> npm test (functions)
#   -> npm test (admin-web) -> npm run test:rules
# The last step starts the Firestore emulator by itself (needs Java).
. "$PSScriptRoot\_common.ps1"
Push-Location $Repo
Say "flutter analyze"
flutter analyze
if ($LASTEXITCODE -ne 0) { Pop-Location; Fail "flutter analyze found issues (above)."; exit 1 }
Say "flutter test"
flutter test
if ($LASTEXITCODE -ne 0) { Pop-Location; Fail "a Flutter test failed (above)."; exit 1 }
Set-Location functions
Say "npx tsc --noEmit  (functions/)"
npx tsc --noEmit
if ($LASTEXITCODE -ne 0) { Pop-Location; Fail "TypeScript errors in functions/ (above)."; exit 1 }
Say "npm test  (functions/)"
npm test
if ($LASTEXITCODE -ne 0) { Pop-Location; Fail "a functions test failed (above)."; exit 1 }
Set-Location ..\admin-web
Say "npm test  (admin-web/)"
npm test
if ($LASTEXITCODE -ne 0) { Pop-Location; Fail "the admin page does not run to the end (above). A throw while it evaluates unhooks every listener below it."; exit 1 }
Set-Location ..\functions
Say "npm run test:rules  (functions/, Firestore emulator)"
npm run test:rules
if ($LASTEXITCODE -ne 0) { Pop-Location; Fail "a security-rules test failed (above). If the emulator did not start, install Java 21+ and run scripts\\test-all.ps1 again."; exit 1 }
Pop-Location
Write-Host "`nAll green." -ForegroundColor Green
