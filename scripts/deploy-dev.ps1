# Tests, then deploys EVERYTHING to the dev project (functions, Firestore rules,
# indexes, Storage rules), registers the Shopify webhooks, and runs the doctor.
. "$PSScriptRoot\_common.ps1"
& "$PSScriptRoot\test-all.ps1"
if ($LASTEXITCODE -ne 0) { exit 1 }
Push-Location "$Repo\functions"
Say "npm run deploy:dev"
npm run deploy:dev
if ($LASTEXITCODE -ne 0) { Pop-Location; Fail "deploy failed (above)."; exit 1 }
Say "npm run webhooks:dev"
npm run webhooks:dev
if ($LASTEXITCODE -ne 0) { Pop-Location; Fail "webhook registration failed (above)."; exit 1 }
Say "npm run doctor"
npm run doctor
$code = $LASTEXITCODE
Pop-Location
exit $code
