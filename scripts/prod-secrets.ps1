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
#   scripts\prod-secrets.ps1            # all of them, from .env.littlebluemarket (the real shop's keys)
#   scripts\prod-secrets.ps1 -Only SHIPTURTLE_API_KEY
#   scripts\prod-secrets.ps1 -FromDev   # INTERIM (Grace, 2026-09-08): copy every secret from the dev
#                                       # project's Secret Manager instead, i.e. the dev test shop's keys.
#                                       # Pair it with SHOPIFY_STORE_DOMAIN = the dev shop in
#                                       # functions\.env.little-blue-cart-prod, or nothing will mint.
param([string]$Only = '', [string]$EnvFile = '', [switch]$FromDev)
. "$PSScriptRoot\_common.ps1"

if ($FromDev) {
  $names = 'SHOPIFY_CLIENT_SECRET','SHOPIFY_STOREFRONT_PRIVATE_TOKEN','SHOPIFY_WEBHOOK_SECRET','SHIPTURTLE_API_KEY','SHIPTURTLE_WEBHOOK_SECRET','WP_APP_PASSWORD','WC_CONSUMER_KEY','WC_CONSUMER_SECRET'
  $failed = @()
  Push-Location "$Repo\functions"
  foreach ($name in $names) {
    if ($Only -and $name -ne $Only) { continue }
    Say "copy $name  dev -> prod  (value not shown)"
    $tmp = New-TemporaryFile
    try {
      $value = (firebase functions:secrets:access $name --project dev 2>$null | Out-String)
      # secrets:access prints the value followed by a newline; keep the value exactly.
      $value = $value -replace "(\r?\n)+$", ''
      if (-not $value) { Write-Host "SKIP  $name  (dev has no value)" -ForegroundColor Yellow; $failed += $name; continue }
      [System.IO.File]::WriteAllText($tmp.FullName, $value)
      firebase functions:secrets:set $name --project prod --data-file $tmp.FullName --force
      if ($LASTEXITCODE -ne 0) { $failed += $name }
    } finally {
      Remove-Item $tmp.FullName -Force -ErrorAction SilentlyContinue
      $value = $null
    }
  }
  Pop-Location
  if ($failed.Count) { Fail "not copied: $($failed -join ', ')"; exit 1 }
  Write-Host "`nProduction now holds the DEV secrets. Next: scripts\deploy-prod.ps1 (functions must be redeployed to pick up new secret versions)." -ForegroundColor Green
  exit 0
}

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
# A Shipturtle key is a JWT (three base64url parts joined by dots). A note pasted after it on the
# same line (it happened, 2026-09-08: 63 characters of text after the token) would break every call,
# so keep the token and drop whatever follows.
$jwt = [regex]::Match($plan['SHIPTURTLE_API_KEY'], '^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+')
if ($jwt.Success -and $jwt.Value.Length -lt $plan['SHIPTURTLE_API_KEY'].Length) {
  Write-Host "SHIPTURTLE_API_KEY: ignoring $($plan['SHIPTURTLE_API_KEY'].Length - $jwt.Value.Length) characters of text after the token" -ForegroundColor Yellow
  $plan['SHIPTURTLE_API_KEY'] = $jwt.Value
}

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
