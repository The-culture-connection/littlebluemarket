# scripts\deploy-check-redesign.ps1
# Reports what is actually configured and reachable on the DEV Firebase project after Phase 6.
# Never points at prod. Exit 1 on any FAIL.
$ErrorActionPreference = 'Continue'
$Project = 'little-blue-610e5'
$Repo = Split-Path $PSScriptRoot -Parent
$fail = 0
function Line($ok, $name, $detail) { $tag = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }; Write-Host ("{0}  {1}  {2}" -f $tag, $name, $detail) -ForegroundColor $c; if (-not $ok) { $script:fail = 1 } }

$active = (firebase use 2>&1 | Out-String)
Line ($active -match $Project) "firebase project is dev" ($active.Trim())

$fns = (firebase functions:list --project $Project 2>&1 | Out-String)
Line ($fns -match 'onTagFollowWritten') "onTagFollowWritten deployed" ''
Line ($fns -match 'onPostWritten') "onPostWritten deployed" ''
Line ($fns -match 'appConfig') "appConfig callable present" ''

$rules = Get-Content (Join-Path $Repo 'firebase/firestore.rules') -Raw
Line ($rules -match 'followedTags') "rules file contains followedTags" ''
Line ($rules -match 'subscribers') "rules file contains hashtag subscribers block" ''

$idx = Get-Content (Join-Path $Repo 'firebase/firestore.indexes.json') -Raw
$hasThreads = $idx -match '"collectionGroup":\s*"threads"' -and $idx -match 'commentCount'
Write-Host ("INFO  threads hot index: {0}" -f $(if ($hasThreads) { 'present' } else { 'absent (N/A if T6.5 concluded not needed)' }))

# appConfig returns a shipturtleUrl (unauthenticated callable in this project per index.ts:417-423)
try {
  $url = "https://us-central1-$Project.cloudfunctions.net/appConfig"
  $resp = Invoke-RestMethod -Method Post -Uri $url -ContentType 'application/json' -Body '{"data":{}}' -TimeoutSec 20
  $st = $resp.result.shipturtleUrl
  Line ([bool]$st) "appConfig.shipturtleUrl" "$st"
} catch { Line $false "appConfig reachable" "$_" }

if ($fail) { Write-Host "`nDeploy check: FAIL" -ForegroundColor Red; exit 1 } else { Write-Host "`nDeploy check: PASS" -ForegroundColor Green; exit 0 }
