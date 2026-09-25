# scripts\verify-redesign.ps1 -Phase <1..7|all>
# One command per phase. Exits non-zero on the first failure. Prints one line per check.
# Usage: pwsh -File scripts\verify-redesign.ps1 -Phase 2
param([Parameter(Mandatory=$true)][string]$Phase)

$ErrorActionPreference = 'Stop'
$Repo = Split-Path $PSScriptRoot -Parent
Push-Location $Repo

function Check($name, [scriptblock]$body) {
  Write-Host ("[{0}] {1} ..." -f $Phase, $name) -NoNewline
  try { & $body; if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) { throw "exit $LASTEXITCODE" }; Write-Host "  PASS" -ForegroundColor Green }
  catch { Write-Host "  FAIL  ($_)" -ForegroundColor Red; Pop-Location; exit 1 }
}

function FlutterTests([string[]]$files) {
  $existing = $files | Where-Object { Test-Path $_ }
  if ($existing.Count -eq 0) { throw "none of the named tests exist yet: $($files -join ', ')" }
  flutter test @existing 2>&1 | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "flutter test failed" }
}

# Always-on checks (every phase)
Check "flutter analyze clean (zero issues)" {
  $out = flutter analyze 2>&1 | Out-String
  if ($out -notmatch 'No issues found') { Write-Host $out; throw 'analyze reported issues' }
}
Check "welcome screen untouched vs main (hard gate 6)" {
  $diff = git diff main -- lib/screens/onboarding/welcome_screen.dart lib/app_assets.dart assets test/welcome_handoff_test.dart
  if ($diff) { Write-Host $diff; throw 'welcome files changed' }
}
Check "no raw Color(0x...) in new widgets" {
  $hits = Select-String -Path lib/widgets/pins/*.dart, lib/widgets/masonry.dart, lib/widgets/cart_pill.dart, lib/widgets/lbm_toast.dart, lib/screens/market/tag_screen.dart -Pattern 'Color\(0x' -ErrorAction SilentlyContinue
  if ($hits) { $hits | Out-Host; throw 'raw colours found' }
}
Check "no heart/like in pins (cart is the like)" {
  $hits = Select-String -Path lib/widgets/pins/*.dart -Pattern 'favorite|Icons\.thumb_up|likeCount' -ErrorAction SilentlyContinue
  if ($hits) { $hits | Out-Host; throw 'like affordance found in pins' }
}
Check "no points/streak/orders UI on You hub or seller shop" {
  $files = @('lib/screens/you/profile_screen.dart','lib/screens/you/sell_screen.dart') | Where-Object { Test-Path $_ }
  $hits = Select-String -Path $files -Pattern "'[^']*(points|Level \d|streak|Orders)[^']*'" -CaseSensitive:$false
  if ($hits) { $hits | Out-Host; throw 'forbidden copy found' }
}

switch ($Phase) {
  '1' { Check "phase 1 tests" { FlutterTests @('test/masonry_test.dart','test/pins_test.dart','test/design_tokens_test.dart') } }
  '2' { Check "phase 2 tests" { FlutterTests @('test/feed_items_test.dart','test/feed_screen_test.dart','test/guest_gating_test.dart','test/screens_smoke_test.dart','test/text_scaling_test.dart') }
        Check "feed goldens exist" { if (-not (Test-Path test/shots/light-feed.png) -or -not (Test-Path test/shots/dark-feed.png)) { throw 'missing shots' } } }
  '3' { Check "phase 3 tests" { FlutterTests @('test/product_detail_test.dart','test/composer_quick_replies_test.dart','test/screens_smoke_test.dart','test/text_scaling_test.dart') }
        Check "'Also in carts with this' is gone" { $h = Select-String -Path lib/screens/market/product_screen.dart -Pattern 'in carts with'; if ($h) { throw 'old section present' } } }
  '4' { Check "phase 4 tests" { FlutterTests @('test/tag_screen_test.dart','test/auth_screens_test.dart','test/screens_smoke_test.dart') }
        Check "no hashtag goes to results" { $h = Select-String -Path lib -Pattern "goToResults\('#" -Recurse; if ($h) { $h | Out-Host; throw 'hashtag still routed to results' } } }
  '5' { Check "phase 5 tests" { FlutterTests @('test/you_hub_test.dart','test/composer_quick_replies_test.dart','test/welcome_handoff_test.dart','test/checkout_sheet_test.dart','test/screens_smoke_test.dart','test/text_scaling_test.dart') }
        Check "no orders route" { $h = Select-String -Path lib/router/app_router.dart -Pattern "'orders'"; if ($h) { throw 'orders route exists' } }
        Check "full flutter test" { flutter test 2>&1 | Out-Host; if ($LASTEXITCODE -ne 0) { throw 'suite red' } } }
  '6' { Check "functions tsc" { Push-Location functions; npx tsc --noEmit; Pop-Location }
        Check "functions unit tests" { Push-Location functions; npm test; Pop-Location }
        Check "rules tests on emulator" { Push-Location functions; npm run test:rules; Pop-Location }
        Check "rules mention followedTags" { $h = Select-String -Path firebase/firestore.rules -Pattern 'followedTags'; if (-not $h) { throw 'rule missing' } } }
  '7' { Check "everything" { & "$PSScriptRoot\test-all.ps1"; if ($LASTEXITCODE -ne 0) { throw 'test-all red' } } }
  'all' { foreach ($p in 1..7) { & $MyInvocation.MyCommand.Path -Phase "$p"; if ($LASTEXITCODE -ne 0) { Pop-Location; exit 1 } } }
  default { Write-Host "unknown phase $Phase"; Pop-Location; exit 2 }
}

Write-Host "Phase ${Phase}: all checks passed." -ForegroundColor Green
Pop-Location
exit 0
