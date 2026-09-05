# Finds out what the stored Shipturtle token can reach. Output contains no secret; paste it all to Claude.
. "$PSScriptRoot\_common.ps1"
Push-Location "$Repo\functions"
npm run probe:shipturtle
Pop-Location
