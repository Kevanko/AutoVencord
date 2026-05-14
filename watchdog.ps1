$ErrorActionPreference = "SilentlyContinue"

$baseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$installer = Join-Path $baseDir "VencordInstallerCli.exe"
$discordRoot = Join-Path $env:LOCALAPPDATA "Discord"
$logPath = Join-Path $baseDir "last-action.log"
$logMaxBytes = 2097152
$script:isPatching = $false

function Rotate-LogIfNeeded {
    if (-not (Test-Path $logPath)) {
        return
    }

    $size = (Get-Item $logPath).Length
    if ($size -lt $logMaxBytes) {
        return
    }

    $backupPath = Join-Path $baseDir "last-action.previous.log"
    if (Test-Path $backupPath) {
        Remove-Item $backupPath -Force -ErrorAction SilentlyContinue
    }

    Move-Item $logPath $backupPath -Force
}

function Write-Log($message) {
    Rotate-LogIfNeeded
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logPath -Value "[$timestamp] $message"
}

function Get-LatestDiscordInstall {
    if (-not (Test-Path $discordRoot)) {
        return $null
    }

    $dirs = Get-ChildItem $discordRoot -Directory |
        Where-Object { $_.Name -like "app-*" } |
        Sort-Object Name -Descending

    if (-not $dirs) {
        return $null
    }

    return $dirs[0]
}

function Test-VencordPatched($appDir) {
    $resources = Join-Path $appDir.FullName "resources"
    $appAsar = Join-Path $resources "app.asar"
    $backupAsar = Join-Path $resources "_app.asar"

    if (-not (Test-Path $appAsar) -or -not (Test-Path $backupAsar)) {
        return $false
    }

    return (Get-Item $appAsar).Length -lt 4096
}

function Patch-Discord {
    if (-not (Test-Path $installer)) {
        Write-Log "Installer not found: $installer"
        return
    }

    if ($script:isPatching) {
        Write-Log "Patch skipped because another patch is already running"
        return
    }

    $script:isPatching = $true

    try {
        Write-Log "Starting patch for Discord at $discordRoot"
        $output = & $installer -install -location $discordRoot 2>&1

        if ($output) {
            $output | ForEach-Object {
                Write-Log "CLI: $_"
            }
        }

        Write-Log "Patch finished"
        Start-Sleep -Seconds 2
    } catch {
        Write-Log "Patch failed: $($_.Exception.Message)"
    } finally {
        $script:isPatching = $false
    }
}

function Invoke-PatchIfNeeded {
    $latest = Get-LatestDiscordInstall

    if (-not $latest) {
        Write-Log "No Discord install found in $discordRoot"
        return
    }

    if (-not (Test-VencordPatched $latest)) {
        Write-Log "Detected unpatched Discord version: $($latest.Name)"
        Patch-Discord
    } else {
        Write-Log "Checked version $($latest.Name): already patched"
    }
}

Write-Log "Watcher started"
Invoke-PatchIfNeeded

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $discordRoot
$watcher.IncludeSubdirectories = $false
$watcher.NotifyFilter = [System.IO.NotifyFilters]'DirectoryName, FileName, LastWrite'
$watcher.EnableRaisingEvents = $true

$action = {
    Start-Sleep -Milliseconds 1500
    Write-Log "Filesystem change detected in Discord folder"
    Invoke-PatchIfNeeded
}

$createdEvent = Register-ObjectEvent -InputObject $watcher -EventName Created -Action $action
$changedEvent = Register-ObjectEvent -InputObject $watcher -EventName Changed -Action $action
$renamedEvent = Register-ObjectEvent -InputObject $watcher -EventName Renamed -Action $action

while ($true) {
    Wait-Event -Timeout 3600 | Out-Null
    Get-Event | Remove-Event

    if (-not (Test-Path $discordRoot)) {
        Write-Log "Discord root missing, waiting for it to appear again"
        Start-Sleep -Seconds 5
    }
}
