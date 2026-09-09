# PRODUCTION deploy. Tests, then deploys EVERYTHING to little-blue-cart-prod
# (functions, Firestore rules, indexes, Storage rules), registers the Shopify
# webhooks on the REAL shop, and runs the production doctor.
#
# Before the first run: scripts\prod-secrets.ps1 (Secret Manager on prod) and
# functions\.env.little-blue-cart-prod (already written). The deploy refuses
# to start while a secret it names is missing.
. "$PSScriptRoot\_common.ps1"
Write-Host "`nThis deploys to PRODUCTION (little-blue-cart-prod) and registers webhooks on the REAL shop." -ForegroundColor Yellow
& "$PSScriptRoot\test-all.ps1"
if ($LASTEXITCODE -ne 0) { exit 1 }
Push-Location "$Repo\functions"
Say "npm run deploy:prod"
npm run deploy:prod
if ($LASTEXITCODE -ne 0) { Pop-Location; Fail "deploy failed (above). A 'secret ... does not exist' line means scripts\prod-secrets.ps1 has not been run; a billing line means the prod project is not on the Blaze plan yet."; exit 1 }
Say "npm run webhooks:prod"
npm run webhooks:prod
if ($LASTEXITCODE -ne 0) { Pop-Location; Fail "webhook registration on the real shop failed (above)."; exit 1 }
Say "npm run doctor:prod"
npm run doctor:prod
$code = $LASTEXITCODE
Pop-Location
exit $code
