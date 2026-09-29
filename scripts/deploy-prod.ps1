# PRODUCTION deploy. Tests, then deploys EVERYTHING to little-blue-cart-prod
# (functions, Firestore rules, indexes, Storage rules), registers the Shopify
# webhooks on the REAL shop, and runs the production doctor.
#
# Before the first run: scripts\prod-secrets.ps1 (Secret Manager on prod) and
# functions\.env.little-blue-cart-prod. The deploy refuses to start while a
# secret it names is missing.
#
#   scripts\deploy-prod.ps1          # the three checks below, then deploy
#   scripts\deploy-prod.ps1 -Force   # deploy anyway, knowing what you skipped
param([switch]$Force)

. "$PSScriptRoot\_common.ps1"

# --------------------------------------------------------------- the checks
#
# Three ways to ship the wrong thing to production, all of which have happened
# or nearly happened, and none of which announce themselves: the deploy runs
# happily and the wrong code is live. They are checked here rather than
# remembered, because the whole point is that you do not notice.
#
# There are several checkouts of this repository on this machine, on different
# branches. `npm run deploy:prod` deploys whatever is in the folder it is run
# from, and says nothing about which folder that is.
if (-not $Force) {
  Push-Location $Repo

  # 1. This folder is on the commit that `main` points at.
  git fetch origin main --quiet 2>$null
  $head = (git rev-parse HEAD).Trim()
  $main = (git rev-parse origin/main 2>$null)
  if ($main) { $main = $main.Trim() }
  $branch = (git rev-parse --abbrev-ref HEAD).Trim()

  if (-not $main) {
    Pop-Location
    Fail "could not read origin/main. Check the network, or run with -Force if you are sure."
    exit 1
  }
  if ($head -ne $main) {
    Write-Host ""
    Write-Host "REFUSING: this folder is not the code that is on main." -ForegroundColor Red
    Write-Host ""
    Write-Host ("  this folder : {0}  ({1})" -f $head.Substring(0, 7), $branch)
    Write-Host ("  origin/main : {0}" -f $main.Substring(0, 7))
    Write-Host ("  folder      : {0}" -f $Repo)
    Write-Host ""
    Write-Host "Production must only ever be deployed from the commit that is on main." -ForegroundColor Yellow
    Write-Host "Either switch this folder to main:" -ForegroundColor Yellow
    Write-Host "    git checkout main; git pull"
    Write-Host "or run the deploy from the folder that already is on main, then:" -ForegroundColor Yellow
    Write-Host "    scripts\deploy-prod.ps1"
    Write-Host ""
    Write-Host "To find that folder:  git worktree list" -ForegroundColor Yellow
    Pop-Location
    exit 1
  }

  # 2. Nothing uncommitted. Production should be a commit somebody can find
  #    again, not whatever happened to be on this disk at the time.
  $dirty = git status --porcelain --untracked-files=no
  if ($dirty) {
    Write-Host ""
    Write-Host "REFUSING: this folder has uncommitted changes." -ForegroundColor Red
    $dirty | ForEach-Object { Write-Host ("    " + $_) }
    Write-Host ""
    Write-Host "Commit and push them, or stash them, then run this again." -ForegroundColor Yellow
    Pop-Location
    exit 1
  }

  Pop-Location

  # 3. The production parameters are in this folder. `.env` files are
  #    gitignored, so a fresh checkout or a worktree has none, and the failure
  #    is a wall of "In non-interactive mode but have no value for" naming
  #    every parameter at once, which reads like a configuration disaster and
  #    is one missing file.
  $prodEnv = Join-Path $Repo "functions\.env.little-blue-cart-prod"
  if (-not (Test-Path $prodEnv)) {
    Write-Host ""
    Write-Host "REFUSING: this folder has no production parameters." -ForegroundColor Red
    Write-Host ""
    Write-Host ("  expected: {0}" -f $prodEnv)
    Write-Host ""
    Write-Host ".env files are gitignored on purpose, so they do not travel between" -ForegroundColor Yellow
    Write-Host "checkouts. Copy it from the folder that has it:" -ForegroundColor Yellow
    Write-Host "    git worktree list        # to find the other folders"
    Write-Host "    copy <that folder>\functions\.env.little-blue-cart-prod functions\"
    exit 1
  }
}

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
