$ErrorActionPreference = "Stop"

$installerUrl = "https://raw.githubusercontent.com/Kevanko/AutoVencord/main/AutoVencord-OneClick.bat"
$tempDir = Join-Path $env:TEMP "AutoVencord"
$batPath = Join-Path $tempDir "AutoVencord-OneClick.bat"

function Enable-Tls12IfAvailable {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]3072
    } catch {}
}

function Download-File($url, $outFile) {
    Enable-Tls12IfAvailable

    if (Get-Command Invoke-WebRequest -ErrorAction SilentlyContinue) {
        Invoke-WebRequest -UseBasicParsing $url -OutFile $outFile
        return
    }

    $client = New-Object System.Net.WebClient
    $client.DownloadFile($url, $outFile)
}

New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

Write-Host "Downloading latest AutoVencord installer..." -ForegroundColor Cyan
Download-File $installerUrl $batPath

$oldSkipSelfUpdate = $env:AUTOVENCORD_SKIP_SELF_UPDATE
$oldNoPause = $env:AUTOVENCORD_NO_PAUSE

try {
    $env:AUTOVENCORD_SKIP_SELF_UPDATE = "1"
    $env:AUTOVENCORD_NO_PAUSE = "1"

    & $batPath
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        throw "AutoVencord installer failed with exit code $exitCode"
    }
} finally {
    $env:AUTOVENCORD_SKIP_SELF_UPDATE = $oldSkipSelfUpdate
    $env:AUTOVENCORD_NO_PAUSE = $oldNoPause
}
