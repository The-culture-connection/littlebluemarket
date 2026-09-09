# Preflight against PRODUCTION (little-blue-cart-prod, the real shop, the live directory).
. "$PSScriptRoot\_common.ps1"
Say "npm run doctor:prod  (functions/)"
Push-Location "$Repo\functions"
npm run doctor:prod
$code = $LASTEXITCODE
Pop-Location
if ($code -ne 0) { Fail "the production doctor found something red. Do what its 'fix ->' line says, then run this again." }
exit $code
