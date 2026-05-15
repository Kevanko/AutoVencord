$ErrorActionPreference = "SilentlyContinue"

$scriptRoot = if ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PWD.Path }
$corePath = Join-Path $scriptRoot "AutoVencord.Core.ps1"

if (-not (Test-Path -LiteralPath $corePath)) {
    exit 50
}

. $corePath
Set-AutoVencordContext -BaseDir $scriptRoot | Out-Null
Start-AutoVencordWatchdogLoop
