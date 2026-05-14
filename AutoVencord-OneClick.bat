@echo off
setlocal

set "PS1=%TEMP%\AutoVencord-setup.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$content = Get-Content -LiteralPath '%~f0'; $start = ($content | Select-String '^#<POWERSHELL>$').LineNumber; if (-not $start) { throw 'Embedded PowerShell script not found.' }; $content[($start)..($content.Length - 1)] | Set-Content -LiteralPath '%PS1%' -Encoding UTF8"
if errorlevel 1 (
    echo Failed to extract embedded PowerShell script.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
set "EXITCODE=%ERRORLEVEL%"
del "%PS1%" >nul 2>&1

if not "%EXITCODE%"=="0" (
    echo.
    echo AutoVencord install failed.
    pause
    exit /b %EXITCODE%
)

pause
exit /b 0

#<POWERSHELL>
$ErrorActionPreference = "Stop"

$baseDir = Join-Path $env:LOCALAPPDATA "AutoVencord"
$installerPath = Join-Path $baseDir "VencordInstallerCli.exe"
$watchdogPath = Join-Path $baseDir "watchdog.ps1"
$uninstallPath = Join-Path $baseDir "uninstall.bat"
$taskName = "AutoVencord Watchdog"
$discordRoot = Join-Path $env:LOCALAPPDATA "Discord"

function Install-Task {
    param(
        [string]$TaskName,
        [string]$ScriptPath
    )

    $commandArgument = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPath`""

    if (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $commandArgument
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Days 3650)

        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
        Start-ScheduledTask -TaskName $TaskName
        return
    }

    & schtasks.exe /Delete /TN $TaskName /F 2>$null | Out-Null
    & schtasks.exe /Create /F /SC ONLOGON /TN $TaskName /TR "powershell.exe $commandArgument" | Out-Null
    & schtasks.exe /Run /TN $TaskName | Out-Null
}

New-Item -ItemType Directory -Force -Path $baseDir | Out-Null

Invoke-WebRequest -UseBasicParsing "https://github.com/Vencord/Installer/releases/latest/download/VencordInstallerCli.exe" -OutFile $installerPath

$watchdogContent = @'
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
'@

$uninstallContent = @'
@echo off
setlocal
set "TASK_NAME=AutoVencord Watchdog"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "if (Get-Command Unregister-ScheduledTask -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName '%TASK_NAME%' -Confirm:$false -ErrorAction SilentlyContinue ^| Out-Null } else { schtasks /Delete /TN ""%TASK_NAME%"" /F ^| Out-Null }"
echo Removed: %TASK_NAME%
pause
'@

Set-Content -LiteralPath $watchdogPath -Value $watchdogContent -Encoding UTF8
Set-Content -LiteralPath $uninstallPath -Value $uninstallContent -Encoding ASCII

Get-Process Discord -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
& $installerPath -install -location $discordRoot

Install-Task -TaskName $taskName -ScriptPath $watchdogPath

Write-Host ""
Write-Host "AutoVencord installed successfully." -ForegroundColor Green
Write-Host "Folder: $baseDir"
Write-Host "Task:   $taskName"
Write-Host ""
