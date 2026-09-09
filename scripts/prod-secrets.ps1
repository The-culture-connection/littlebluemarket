# Puts the PRODUCTION secrets into Secret Manager on little-blue-cart-prod,
# reading them from PARENT\.env.littlebluemarket (the file that already holds
# the real shop's credentials). Values go straight from the file into
# `firebase functions:secrets:set` over stdin: nothing is printed, nothing
# lands in shell history.
#
# What it sets, and where each value comes from:
#   SHOPIFY_CLIENT_SECRET             .env.littlebluemarket SHOPIFY_CLIENT_SECRET
#   SHOPIFY_STOREFRONT_PRIVATE_TOKEN  .env.littlebluemarket SHOPIFY_STOREFRONT_PRIVATE_TOKEN
#   SHOPIFY_WEBHOOK_SECRET            same as SHOPIFY_CLIENT_SECRET (webhooks the app registers are signed with it)
#   SHIPTURTLE_API_KEY                .env.littlebluemarket SHIPTURTLE_API_KEY_ORDER (or SHIPTURTLE_API_KEY if present)
#   SHIPTURTLE_WEBHOOK_SECRET         .env.littlebluemarket SHIPTURTLE_WEBHOOK_SECRET, else "unsigned" (Shipturtle does not sign)
#   WP_APP_PASSWORD, WC_CONSUMER_KEY, WC_CONSUMER_SECRET   .env.littlebluemarket (the live site; same as dev)
#
# Re-running overwrites (a new secret version), which is how a rotated key gets in.
#   scripts\prod-secrets.ps1            # all of them
#   scripts\prod-secrets.ps1 -Only SHIPTURTLE_API_KEY
param([string]$Only = '', [string]$EnvFile = '')
. "$PSScriptRoot\_common.ps1"
if (-not $EnvFile) { $EnvFile = Join-Path (Split-Path -Parent $Repo) ".env.littlebluemarket" }
if (-not (Test-Path $EnvFile)) { Fail "$EnvFile not found. It is the file with the real shop's keys (SHOPIFY_CLIENT_SECRET, SHOPIFY_STOREFRONT_PRIVATE_TOKEN, SHIPTURTLE_API_KEY_ORDER, WP_APP_PASSWORD, WC_CONSUMER_KEY, WC_CONSUMER_SECRET)."; exit 1 }

$values = @{}
foreach ($line in Get-Content $EnvFile) {
  if ($line -match '^\s*([A-Za-z0-9_ ]+?)\s*=\s*(.*)$') {
    $k = $Matches[1].Trim(); $v = $Matches[2].Trim()
    if ($v.StartsWith('"') -and $v.EndsWith('"') -and $v.Length -ge 2) { $v = $v.Substring(1, $v.Length - 2) }
    $values[$k] = $v
  }
}
function Pick([string[]]$keys) { foreach ($k in $keys) { if ($values.ContainsKey($k) -and $values[$k]) { return $values[$k] } }; return '' }

$plan = [ordered]@{
  'SHOPIFY_CLIENT_SECRET'            = (Pick @('SHOPIFY_CLIENT_SECRET'))
  'SHOPIFY_STOREFRONT_PRIVATE_TOKEN' = (Pick @('SHOPIFY_STOREFRONT_PRIVATE_TOKEN'))
  'SHOPIFY_WEBHOOK_SECRET'           = (Pick @('SHOPIFY_WEBHOOK_SECRET', 'SHOPIFY_CLIENT_SECRET'))
  'SHIPTURTLE_API_KEY'               = (Pick @('SHIPTURTLE_API_KEY', 'SHIPTURTLE_API_KEY_ORDER', 'SHIPTURTLE_API_KEY_PRODUCT'))
  'SHIPTURTLE_WEBHOOK_SECRET'        = (Pick @('SHIPTURTLE_WEBHOOK_SECRET'))
  'WP_APP_PASSWORD'                  = (Pick @('WP_APP_PASSWORD'))
  'WC_CONSUMER_KEY'                  = (Pick @('WC_CONSUMER_KEY'))
  'WC_CONSUMER_SECRET'               = (Pick @('WC_CONSUMER_SECRET'))
}
if (-not $plan['SHIPTURTLE_WEBHOOK_SECRET']) { $plan['SHIPTURTLE_WEBHOOK_SECRET'] = 'unsigned' }

$failed = @()
Push-Location "$Repo\functions"
foreach ($name in $plan.Keys) {
  if ($Only -and $name -ne $Only) { continue }
  $value = $plan[$name]
  if (-not $value) { Write-Host "SKIP  $name  (no value in $(Split-Path $EnvFile -Leaf))" -ForegroundColor Yellow; $failed += $name; continue }
  Say "firebase functions:secrets:set $name --project prod  (value: $($value.Length) characters, not shown)"
  $tmp = New-TemporaryFile
  try {
    [System.IO.File]::WriteAllText($tmp.FullName, $value)
    firebase functions:secrets:set $name --project prod --data-file $tmp.FullName --force
    if ($LASTEXITCODE -ne 0) { $failed += $name }
  } finally {
    Remove-Item $tmp.FullName -Force -ErrorAction SilentlyContinue
  }
}
Pop-Location
if ($failed.Count) { Fail "not set: $($failed -join ', ')"; exit 1 }
Write-Host "`nAll production secrets set. Next: scripts\deploy-prod.ps1" -ForegroundColor Green
