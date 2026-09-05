# Preflight. Run this at the start of every session. All lines should be PASS, WARN, MANUAL or SKIP.
. "$PSScriptRoot\_common.ps1"
Say "npm run doctor  (functions/)"
Push-Location "$Repo\functions"
npm run doctor
$code = $LASTEXITCODE
Pop-Location
if ($code -ne 0) { Fail "the doctor found something red. Do what its 'fix ->' line says, then run this again." }
exit $code
