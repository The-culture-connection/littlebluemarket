# Prints the Firestore document for a seller claim code. Paste it into the console, then the seller redeems the code in the app.
#   scripts\issue-claim-code.ps1 -Vendor "Snowboard Vendor" -Email grace-s+seller1@example.com
param([Parameter(Mandatory=$true)][string]$Vendor, [string]$Email = '', [string]$Code = '', [string]$VendorId = '')
. "$PSScriptRoot\_common.ps1"
Push-Location "$Repo\functions"
$args = @()
if ($Code) { $args += $Code } else { $args += '--generate' }
$args += @('--vendor', $Vendor)
if ($Email) { $args += @('--email', $Email) }
if ($VendorId) { $args += @('--vendor-id', $VendorId) }
node scripts/claim-code-hash.mjs @args
Pop-Location
