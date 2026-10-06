param([switch]$ChinaMirrors, [switch]$GreenOnly)
$ErrorActionPreference = "Stop"
$BuildArguments = @()
if ($ChinaMirrors) { $BuildArguments += "--cn-mirrors" }
if ($GreenOnly) { $BuildArguments += "--green-only" }
python (Join-Path $PSScriptRoot "build_windows.py") @BuildArguments
exit $LASTEXITCODE
