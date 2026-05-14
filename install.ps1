$ErrorActionPreference = "Stop"

$installerUrl = "https://raw.githubusercontent.com/Kevanko/AutoVencord/main/AutoVencord-OneClick.bat"
$tempDir = Join-Path $env:TEMP "AutoVencord"
$batPath = Join-Path $tempDir "AutoVencord-OneClick.bat"
$installedBaseDir = Join-Path $env:LOCALAPPDATA "AutoVencord"
$uninstallPath = Join-Path $installedBaseDir "uninstall.bat"
$windowTitle = "AutoVencord Console Menu"
$taskName = "AutoVencord Watchdog"

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

function Write-Banner {
    Write-Host "============================================================" -ForegroundColor DarkCyan
    Write-Host "                    AutoVencord Console Menu" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "Choose an action with Up/Down arrows and press Enter." -ForegroundColor DarkGray
    Write-Host ""
}

function Get-WatchdogState {
    if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
        try {
            $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
            return [string]$task.State
        } catch {
            return "Not installed"
        }
    }

    try {
        $output = & schtasks.exe /Query /TN $taskName /FO LIST 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $output) {
            return "Not installed"
        }

        $statusLine = $output | Where-Object { $_ -like "Status:*" } | Select-Object -First 1
        if ($statusLine) {
            return ($statusLine -replace "^Status:\s*", "").Trim()
        }
    } catch {}

    return "Unknown"
}

function Write-StatusPanel {
    $isInstalled = Test-Path $uninstallPath
    $watchdogState = Get-WatchdogState

    if ($isInstalled) {
        Write-Host ("Installed : Yes") -ForegroundColor Green
    } else {
        Write-Host ("Installed : No") -ForegroundColor Yellow
    }

    if ($watchdogState -match "Ready|Running") {
        Write-Host ("Watchdog  : Active ({0})" -f $watchdogState) -ForegroundColor Green
    } elseif ($watchdogState -eq "Not installed") {
        Write-Host ("Watchdog  : Not installed") -ForegroundColor Yellow
    } else {
        Write-Host ("Watchdog  : Inactive ({0})" -f $watchdogState) -ForegroundColor Yellow
    }

    Write-Host ""
}

function Write-MenuLine {
    param(
        [string]$Label,
        [bool]$Selected
    )

    $text = ("  {0}" -f $Label).PadRight(34)

    if ($Selected) {
        Write-Host ($text + " <") -ForegroundColor Black -BackgroundColor Cyan
    } else {
        Write-Host ($text + "  ") -ForegroundColor Gray
    }
}

function Show-Menu {
    param(
        [string[]]$Options,
        [string]$Title
    )

    $index = 0

    while ($true) {
        Clear-Host
        $Host.UI.RawUI.WindowTitle = $windowTitle
        Write-Banner
        Write-Host ("{0}" -f $Title) -ForegroundColor Green
        Write-Host ""
        Write-StatusPanel

        for ($i = 0; $i -lt $Options.Length; $i++) {
            Write-MenuLine -Label $Options[$i] -Selected ($i -eq $index)
        }

        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

        if ($key.VirtualKeyCode -eq 38) {
            if ($index -gt 0) {
                $index--
            }

            continue
        }

        if ($key.VirtualKeyCode -eq 40) {
            if ($index -lt ($Options.Length - 1)) {
                $index++
            }

            continue
        }

        if ($key.VirtualKeyCode -eq 13) {
            return $index
        }
    }
}

function Invoke-Install {
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
}

function Invoke-Uninstall {
    if (-not (Test-Path $uninstallPath)) {
        throw "AutoVencord is not installed. Missing file: $uninstallPath"
    }

    Write-Host "Running AutoVencord uninstaller..." -ForegroundColor Yellow
    & $uninstallPath
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        throw "AutoVencord uninstaller failed with exit code $exitCode"
    }
}

function Invoke-Update {
    Write-Host "Updating AutoVencord..." -ForegroundColor Cyan
    Invoke-Install
}

function Open-InstallFolder {
    New-Item -ItemType Directory -Force -Path $installedBaseDir | Out-Null
    Start-Process explorer.exe $installedBaseDir
}

$selection = Show-Menu -Options @("Install AutoVencord", "Update AutoVencord", "Uninstall AutoVencord", "Open AutoVencord Folder") -Title "Setup / Maintenance"

Clear-Host

if ($selection -eq 0) {
    Invoke-Install
} elseif ($selection -eq 1) {
    Invoke-Update
} elseif ($selection -eq 2) {
    Invoke-Uninstall
} else {
    Open-InstallFolder
}
