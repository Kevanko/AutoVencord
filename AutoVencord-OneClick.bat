@echo off
setlocal

if "%AUTOVENCORD_SKIP_SELF_UPDATE%"=="1" goto AfterSelfUpdate

set "SELFUPDATE=%TEMP%\AutoVencord-self-update.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$content = Get-Content -LiteralPath '%~f0'; $start = ($content | Select-String '^#<SELFUPDATE>$').LineNumber; $end = ($content | Select-String '^#</SELFUPDATE>$').LineNumber; if (-not $start -or -not $end -or $end -le $start) { throw 'Embedded self-update script not found.' }; $content[($start)..($end - 2)] | Set-Content -LiteralPath '%SELFUPDATE%' -Encoding UTF8"
if errorlevel 1 goto AfterSelfUpdate

powershell -NoProfile -ExecutionPolicy Bypass -File "%SELFUPDATE%" -SelfPath "%~f0"
set "UPDATE_EXIT=%ERRORLEVEL%"
del "%SELFUPDATE%" >nul 2>&1
if "%UPDATE_EXIT%"=="42" exit /b 0

:AfterSelfUpdate
set "PS1=%TEMP%\AutoVencord-setup.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$content = Get-Content -LiteralPath '%~f0'; $start = ($content | Select-String '^#<POWERSHELL>$').LineNumber; if (-not $start) { throw 'Embedded PowerShell script not found.' }; $content[($start)..($content.Length - 1)] | Set-Content -LiteralPath '%PS1%' -Encoding UTF8"
if errorlevel 1 (
    echo Failed to extract embedded PowerShell script.
    call :MaybePause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -SourceBatPath "%~f0"
set "EXITCODE=%ERRORLEVEL%"
del "%PS1%" >nul 2>&1

if not "%EXITCODE%"=="0" (
    echo.
    echo AutoVencord install failed.
    call :MaybePause
    exit /b %EXITCODE%
)

call :MaybePause
exit /b 0

:MaybePause
if not "%AUTOVENCORD_NO_PAUSE%"=="1" pause
exit /b 0

#<SELFUPDATE>
param(
    [string]$SelfPath
)

$ErrorActionPreference = "SilentlyContinue"
$latestUrl = "https://raw.githubusercontent.com/Kevanko/AutoVencord/main/AutoVencord-OneClick.bat"
$latestFallbackUrl = "https://github.com/Kevanko/AutoVencord/raw/main/AutoVencord-OneClick.bat"
$freshMarker = "function Invoke-SchtasksSafe {"

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

function Test-FreshPayload($path) {
    if (-not (Test-Path $path)) {
        return $false
    }

    try {
        $content = Get-Content -LiteralPath $path -Raw
        return $content.Contains($freshMarker)
    } catch {
        return $false
    }
}

function Get-SelfUpdateCandidateUrls() {
    return @(
        $latestUrl,
        $latestFallbackUrl,
        ("{0}?raw=1" -f $latestFallbackUrl)
    )
}

function Download-FreshBatch($outFile) {
    $lastError = $null

    foreach ($url in (Get-SelfUpdateCandidateUrls)) {
        try {
            Download-File $url $outFile

            if (Test-FreshPayload $outFile) {
                return
            }
        } catch {
            $lastError = $_
        }
    }

    if ($lastError) {
        throw $lastError
    }

    throw "Downloaded AutoVencord batch is stale or invalid."
}

function Test-SameFile($left, $right) {
    if (-not (Test-Path $left) -or -not (Test-Path $right)) {
        return $false
    }

    try {
        $a = [System.IO.File]::ReadAllBytes($left)
        $b = [System.IO.File]::ReadAllBytes($right)

        if ($a.Length -ne $b.Length) {
            return $false
        }

        for ($i = 0; $i -lt $a.Length; $i++) {
            if ($a[$i] -ne $b[$i]) {
                return $false
            }
        }

        return $true
    } catch {
        return $false
    }
}

try {
    if (-not $SelfPath -or -not (Test-Path $SelfPath)) {
        exit 0
    }

    $tempBat = Join-Path $env:TEMP ("AutoVencord-OneClick-" + [guid]::NewGuid().ToString() + ".bat")
    Download-FreshBatch $tempBat

    if (Test-SameFile $SelfPath $tempBat) {
        Remove-Item $tempBat -Force -ErrorAction SilentlyContinue
        exit 0
    }

    Write-Host ""
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host "              AutoVencord Update" -ForegroundColor Green
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host "A newer installer is available on GitHub." -ForegroundColor White
    Write-Host "Press Enter or Y to update, N to continue." -ForegroundColor DarkGray
    Write-Host ""

    $answer = Read-Host "Update now? [Y/n]"
    if ($answer -match '^(n|no)$') {
        Remove-Item $tempBat -Force -ErrorAction SilentlyContinue
        Write-Host "Update skipped." -ForegroundColor Yellow
        Start-Sleep -Seconds 1
        exit 0
    }

    $helper = Join-Path $env:TEMP ("AutoVencord-restart-" + [guid]::NewGuid().ToString() + ".cmd")
    $helperContent = @"
@echo off
timeout /t 1 /nobreak >nul
copy /y "$tempBat" "$SelfPath" >nul
if errorlevel 1 (
    echo Failed to replace AutoVencord installer.
    pause
    exit /b 1
)
start "" "$SelfPath"
del "$tempBat" >nul 2>nul
del "%~f0" >nul 2>nul
"@

    Set-Content -LiteralPath $helper -Value $helperContent -Encoding ASCII
    Write-Host "Updating and restarting installer..." -ForegroundColor Green
    Start-Process -FilePath $helper -WindowStyle Normal
    exit 42
} catch {
    if ($tempBat) {
        Remove-Item $tempBat -Force -ErrorAction SilentlyContinue
    }

    Write-Host "Update check skipped: $($_.Exception.Message)" -ForegroundColor Yellow
    Start-Sleep -Seconds 1
    exit 0
}
#</SELFUPDATE>

#<POWERSHELL>
param(
    [string]$SourceBatPath
)

$ErrorActionPreference = "Stop"

$baseDir = Join-Path $env:LOCALAPPDATA "AutoVencord"
$installerPath = Join-Path $baseDir "VencordInstallerCli.exe"
$installerBatchCopyPath = Join-Path $baseDir "AutoVencord-OneClick.bat"
$watchdogPath = Join-Path $baseDir "watchdog.ps1"
$uninstallPath = Join-Path $baseDir "uninstall.bat"
$taskName = "AutoVencord Watchdog"
$discordRoot = Join-Path $env:LOCALAPPDATA "Discord"
$downloadUrl = "https://github.com/Vencord/Installer/releases/latest/download/VencordInstallerCli.exe"
$logPath = Join-Path $baseDir "last-action.log"

function Write-SetupLog($message) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logPath -Value "[$timestamp] SETUP: $message"
}

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

function Invoke-SchtasksSafe {
    param(
        [string[]]$Arguments,
        [switch]$IgnoreExitCode
    )

    $originalPreferenceExists = Test-Path variable:PSNativeCommandUseErrorActionPreference
    if ($originalPreferenceExists) {
        $originalPreference = $PSNativeCommandUseErrorActionPreference
    }

    try {
        if ($originalPreferenceExists) {
            $PSNativeCommandUseErrorActionPreference = $false
        }

        $output = & schtasks.exe @Arguments 2>&1
        $exitCode = $LASTEXITCODE

        return [pscustomobject]@{
            Output = @($output)
            ExitCode = $exitCode
        }
    } finally {
        if ($originalPreferenceExists) {
            $PSNativeCommandUseErrorActionPreference = $originalPreference
        }
    }
}

function Stop-ExistingTask {
    if (Get-Command Stop-ScheduledTask -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue | Out-Null
    }

    $null = Invoke-SchtasksSafe -Arguments @("/End", "/TN", $taskName) -IgnoreExitCode
}

function Install-Task {
    param(
        [string]$TaskName,
        [string]$ScriptPath
    )

    $commandArgument = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPath`""

    Stop-ExistingTask

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

    $null = Invoke-SchtasksSafe -Arguments @("/Delete", "/TN", $TaskName, "/F") -IgnoreExitCode

    $createResult = Invoke-SchtasksSafe -Arguments @("/Create", "/F", "/SC", "ONLOGON", "/TN", $TaskName, "/TR", "powershell.exe $commandArgument")
    if ($createResult.ExitCode -ne 0) {
        throw "schtasks /Create failed with exit code $($createResult.ExitCode): $($createResult.Output -join ' ')"
    }

    $runResult = Invoke-SchtasksSafe -Arguments @("/Run", "/TN", $TaskName)
    if ($runResult.ExitCode -ne 0) {
        throw "schtasks /Run failed with exit code $($runResult.ExitCode): $($runResult.Output -join ' ')"
    }
}

function Get-DiscordAppVersion($directoryName) {
    $raw = $directoryName -replace "^app-", ""

    try {
        return [version]$raw
    } catch {
        return [version]"0.0.0.0"
    }
}

function Get-LatestDiscordInstall {
    if (-not (Test-Path $discordRoot)) {
        return $null
    }

    $latest = $null
    $latestVersion = [version]"0.0.0.0"
    $latestWriteTime = [datetime]::MinValue

    $dirs = Get-ChildItem $discordRoot -ErrorAction SilentlyContinue |
        Where-Object { $_.PSIsContainer -and $_.Name -like "app-*" }

    foreach ($dir in $dirs) {
        $version = Get-DiscordAppVersion $dir.Name

        if (($version -gt $latestVersion) -or ($version -eq $latestVersion -and $dir.LastWriteTimeUtc -gt $latestWriteTime)) {
            $latest = $dir
            $latestVersion = $version
            $latestWriteTime = $dir.LastWriteTimeUtc
        }
    }

    return $latest
}

function Test-DiscordUpdaterActive {
    $processes = Get-Process -ErrorAction SilentlyContinue |
        Where-Object { @("Update", "Squirrel") -contains $_.ProcessName }

    foreach ($process in $processes) {
        $path = $null

        try {
            $path = $process.Path
        } catch {}

        if ($path -and ($path.StartsWith($discordRoot, [System.StringComparison]::OrdinalIgnoreCase) -or $path -like "*\SquirrelTemp\*")) {
            return $true
        }
    }

    $squirrelTemp = Join-Path $discordRoot "SquirrelTemp"
    if (Test-Path $squirrelTemp) {
        try {
            if ((Get-Item $squirrelTemp).LastWriteTimeUtc -gt (Get-Date).ToUniversalTime().AddMinutes(-5)) {
                return $true
            }
        } catch {}
    }

    return $false
}

function Test-FileStable($path) {
    if (-not (Test-Path $path)) {
        return $false
    }

    try {
        $first = Get-Item $path
        if ($first.Length -le 0) {
            return $false
        }

        Start-Sleep -Seconds 2

        $second = Get-Item $path
        if ($first.Length -ne $second.Length -or $first.LastWriteTimeUtc -ne $second.LastWriteTimeUtc) {
            return $false
        }

        $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        $stream.Close()
        return $true
    } catch {
        return $false
    }
}

function Test-DiscordInstallReady($appDir) {
    if (-not $appDir) {
        return $false
    }

    $resources = Join-Path $appDir.FullName "resources"
    $appAsar = Join-Path $resources "app.asar"
    $buildInfo = Join-Path $resources "build_info.json"

    if (-not (Test-Path $resources) -or -not (Test-Path $appAsar) -or -not (Test-Path $buildInfo)) {
        return $false
    }

    return Test-FileStable $appAsar
}

function Wait-DiscordReadyForInitialPatch {
    $deadline = (Get-Date).AddMinutes(5)

    while ((Get-Date) -lt $deadline) {
        if (Test-DiscordUpdaterActive) {
            Write-SetupLog "Discord updater is active, waiting before initial patch"
            Start-Sleep -Seconds 10
            continue
        }

        $latest = Get-LatestDiscordInstall
        if ($latest -and (Test-DiscordInstallReady $latest)) {
            return $true
        }

        Start-Sleep -Seconds 10
    }

    return $false
}

function Invoke-VencordInstallerCli {
    param(
        [string]$InstallerPath,
        [string]$DiscordRoot
    )

    $stdoutPath = Join-Path $baseDir ("cli-stdout-" + [guid]::NewGuid().ToString() + ".log")
    $stderrPath = Join-Path $baseDir ("cli-stderr-" + [guid]::NewGuid().ToString() + ".log")

    try {
        $process = Start-Process -FilePath $InstallerPath -ArgumentList @("-install", "-location", $DiscordRoot) -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        $exitCode = $process.ExitCode
    } finally {
        $output = @()

        if (Test-Path $stdoutPath) {
            $output += Get-Content -LiteralPath $stdoutPath -ErrorAction SilentlyContinue
            Remove-Item $stdoutPath -Force -ErrorAction SilentlyContinue
        }

        if (Test-Path $stderrPath) {
            $output += Get-Content -LiteralPath $stderrPath -ErrorAction SilentlyContinue
            Remove-Item $stderrPath -Force -ErrorAction SilentlyContinue
        }
    }

    return [pscustomobject]@{
        Output = $output
        ExitCode = $exitCode
    }
}

New-Item -ItemType Directory -Force -Path $baseDir | Out-Null
Write-SetupLog "Setup started"
Stop-ExistingTask

if ($SourceBatPath -and (Test-Path $SourceBatPath)) {
    Copy-Item -LiteralPath $SourceBatPath -Destination $installerBatchCopyPath -Force
    Write-SetupLog "Installer batch copied"
}

Write-Host "Downloading official Vencord installer..."
Download-File $downloadUrl $installerPath
Write-SetupLog "Installer downloaded"

$watchdogContent = @'
$ErrorActionPreference = "SilentlyContinue"

$baseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$installer = Join-Path $baseDir "VencordInstallerCli.exe"
$discordRoot = Join-Path $env:LOCALAPPDATA "Discord"
$logPath = Join-Path $baseDir "last-action.log"
$logMaxBytes = 2097152
$debounceSeconds = 5
$retryDelaySeconds = 10
$maxReadyWaitSeconds = 300
$periodicCheckSeconds = 1800
$script:isChecking = $false

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

function Get-DiscordAppVersion($directoryName) {
    $raw = $directoryName -replace "^app-", ""

    try {
        return [version]$raw
    } catch {
        return [version]"0.0.0.0"
    }
}

function Get-LatestDiscordInstall {
    if (-not (Test-Path $discordRoot)) {
        return $null
    }

    $latest = $null
    $latestVersion = [version]"0.0.0.0"
    $latestWriteTime = [datetime]::MinValue

    $dirs = Get-ChildItem $discordRoot -ErrorAction SilentlyContinue |
        Where-Object { $_.PSIsContainer -and $_.Name -like "app-*" }

    foreach ($dir in $dirs) {
        $version = Get-DiscordAppVersion $dir.Name

        if (($version -gt $latestVersion) -or ($version -eq $latestVersion -and $dir.LastWriteTimeUtc -gt $latestWriteTime)) {
            $latest = $dir
            $latestVersion = $version
            $latestWriteTime = $dir.LastWriteTimeUtc
        }
    }

    return $latest
}

function Test-DiscordUpdaterActive {
    $processes = Get-Process -ErrorAction SilentlyContinue |
        Where-Object { @("Update", "Squirrel") -contains $_.ProcessName }

    foreach ($process in $processes) {
        $path = $null

        try {
            $path = $process.Path
        } catch {}

        if ($path -and ($path.StartsWith($discordRoot, [System.StringComparison]::OrdinalIgnoreCase) -or $path -like "*\SquirrelTemp\*")) {
            return $true
        }
    }

    $squirrelTemp = Join-Path $discordRoot "SquirrelTemp"
    if (Test-Path $squirrelTemp) {
        try {
            if ((Get-Item $squirrelTemp).LastWriteTimeUtc -gt (Get-Date).ToUniversalTime().AddMinutes(-5)) {
                return $true
            }
        } catch {}
    }

    return $false
}

function Test-FileStable($path) {
    if (-not (Test-Path $path)) {
        return $false
    }

    try {
        $first = Get-Item $path
        if ($first.Length -le 0) {
            return $false
        }

        Start-Sleep -Seconds 2

        $second = Get-Item $path
        if ($first.Length -ne $second.Length -or $first.LastWriteTimeUtc -ne $second.LastWriteTimeUtc) {
            return $false
        }

        $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        $stream.Close()
        return $true
    } catch {
        return $false
    }
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

function Test-DiscordInstallReady($appDir) {
    if (-not $appDir) {
        return $false
    }

    $resources = Join-Path $appDir.FullName "resources"
    $appAsar = Join-Path $resources "app.asar"
    $buildInfo = Join-Path $resources "build_info.json"

    if (-not (Test-Path $resources) -or -not (Test-Path $appAsar) -or -not (Test-Path $buildInfo)) {
        return $false
    }

    return Test-FileStable $appAsar
}

function Wait-LatestDiscordInstallReady {
    $deadline = (Get-Date).AddSeconds($maxReadyWaitSeconds)
    $loggedUpdater = $false
    $lastLoggedApp = $null

    while ((Get-Date) -lt $deadline) {
        $latest = Get-LatestDiscordInstall

        if (-not $latest) {
            Write-Log "No Discord install found while waiting for readiness"
            Start-Sleep -Seconds $retryDelaySeconds
            continue
        }

        if (Test-DiscordUpdaterActive) {
            if (-not $loggedUpdater) {
                Write-Log "Discord updater is active, waiting before patching"
                $loggedUpdater = $true
            }

            Start-Sleep -Seconds $retryDelaySeconds
            continue
        }

        if (Test-DiscordInstallReady $latest) {
            return $latest
        }

        if ($lastLoggedApp -ne $latest.Name) {
            Write-Log "Discord install is not ready yet: $($latest.Name)"
            $lastLoggedApp = $latest.Name
        }

        Start-Sleep -Seconds $retryDelaySeconds
    }

    Write-Log "Discord install did not become ready in $maxReadyWaitSeconds seconds"
    return $null
}

function Patch-Discord {
    if (-not (Test-Path $installer)) {
        Write-Log "Installer not found: $installer"
        return $false
    }

    try {
        Write-Log "Starting patch for Discord at $discordRoot"
        $stdoutPath = Join-Path $baseDir ("cli-stdout-" + [guid]::NewGuid().ToString() + ".log")
        $stderrPath = Join-Path $baseDir ("cli-stderr-" + [guid]::NewGuid().ToString() + ".log")

        try {
            $process = Start-Process -FilePath $installer -ArgumentList @("-install", "-location", $discordRoot) -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
            $exitCode = $process.ExitCode
        } finally {
            $output = @()

            if (Test-Path $stdoutPath) {
                $output += Get-Content -LiteralPath $stdoutPath -ErrorAction SilentlyContinue
                Remove-Item $stdoutPath -Force -ErrorAction SilentlyContinue
            }

            if (Test-Path $stderrPath) {
                $output += Get-Content -LiteralPath $stderrPath -ErrorAction SilentlyContinue
                Remove-Item $stderrPath -Force -ErrorAction SilentlyContinue
            }
        }

        if ($output) {
            $output | ForEach-Object {
                Write-Log "CLI: $_"
            }
        }

        if ($exitCode -ne 0) {
            Write-Log "Patch failed with exit code $exitCode"
            return $false
        }

        Write-Log "Patch finished"
        return $true
    } catch {
        Write-Log "Patch failed: $($_.Exception.Message)"
        return $false
    }
}

function Invoke-PatchIfNeeded {
    if ($script:isChecking) {
        Write-Log "Check skipped because another check is already running"
        return
    }

    $script:isChecking = $true

    try {
        $latest = Get-LatestDiscordInstall

        if (-not $latest) {
            Write-Log "No Discord install found in $discordRoot"
            return
        }

        if (Test-VencordPatched $latest) {
            Write-Log "Checked version $($latest.Name): already patched"
            return
        }

        Write-Log "Detected unpatched Discord version: $($latest.Name)"

        $ready = Wait-LatestDiscordInstallReady
        if (-not $ready) {
            Write-Log "Patch postponed because Discord is still updating"
            return
        }

        if (Test-VencordPatched $ready) {
            Write-Log "Version $($ready.Name) became patched while waiting"
            return
        }

        if (Patch-Discord) {
            Start-Sleep -Seconds 2
            $verified = Get-LatestDiscordInstall

            if ($verified -and (Test-VencordPatched $verified)) {
                Write-Log "Patch verified for $($verified.Name)"
            } else {
                Write-Log "Patch verification failed, will retry on next event or periodic check"
            }
        }
    } finally {
        $script:isChecking = $false
    }
}

function Start-Watcher {
    while (-not (Test-Path $discordRoot)) {
        Write-Log "Discord root missing, waiting for it to appear"
        Start-Sleep -Seconds 30
    }

    $watcher = New-Object System.IO.FileSystemWatcher
    $watcher.Path = $discordRoot
    $watcher.IncludeSubdirectories = $true
    $watcher.NotifyFilter = [System.IO.NotifyFilters]::DirectoryName -bor [System.IO.NotifyFilters]::FileName -bor [System.IO.NotifyFilters]::LastWrite -bor [System.IO.NotifyFilters]::Size
    $watcher.EnableRaisingEvents = $true

    Register-ObjectEvent -InputObject $watcher -EventName Created -SourceIdentifier "AutoVencord.Created" | Out-Null
    Register-ObjectEvent -InputObject $watcher -EventName Changed -SourceIdentifier "AutoVencord.Changed" | Out-Null
    Register-ObjectEvent -InputObject $watcher -EventName Renamed -SourceIdentifier "AutoVencord.Renamed" | Out-Null

    Write-Log "Watcher started"
    Invoke-PatchIfNeeded

    while ($true) {
        $event = Wait-Event -Timeout $periodicCheckSeconds

        if ($event) {
            Start-Sleep -Seconds $debounceSeconds
            Get-Event | Remove-Event
            Write-Log "Discord filesystem change batch detected"
            Invoke-PatchIfNeeded
        } else {
            Write-Log "Periodic safety check"
            Invoke-PatchIfNeeded
        }
    }
}

Start-Watcher
'@

$uninstallContent = @"
@echo off
setlocal
set "TASK_NAME=AutoVencord Watchdog"
set "BASE_DIR=%~dp0"
set "SELF=%~f0"
set "CLEANUP=%TEMP%\AutoVencord-cleanup-%RANDOM%%RANDOM%.cmd"
echo Running AutoVencord uninstall...
schtasks /End /TN "%TASK_NAME%" >nul 2>&1
schtasks /Delete /TN "%TASK_NAME%" /F >nul 2>&1
echo Removed: %TASK_NAME%
del /f /q "%BASE_DIR%watchdog.ps1" >nul 2>&1
del /f /q "%BASE_DIR%VencordInstallerCli.exe" >nul 2>&1
del /f /q "%BASE_DIR%AutoVencord-OneClick.bat" >nul 2>&1
del /f /q "%BASE_DIR%last-action.log" >nul 2>&1
del /f /q "%BASE_DIR%last-action.previous.log" >nul 2>&1
> "%CLEANUP%" echo @echo off
>> "%CLEANUP%" echo ping 127.0.0.1 -n 3 ^>nul
>> "%CLEANUP%" echo del /f /q "%SELF%" ^>nul 2^>^&1
>> "%CLEANUP%" echo rmdir "%BASE_DIR%" ^>nul 2^>^&1
>> "%CLEANUP%" echo del /f /q "%%~f0" ^>nul 2^>^&1
start "" /min cmd /c "%CLEANUP%"
echo Removed files from: %BASE_DIR%
if /I not "%AUTOVENCORD_NO_PAUSE%"=="1" pause >nul
"@

Set-Content -LiteralPath $watchdogPath -Value $watchdogContent -Encoding UTF8
Set-Content -LiteralPath $uninstallPath -Value $uninstallContent -Encoding ASCII
Write-SetupLog "Files written"

if (Test-Path $discordRoot) {
    Get-Process Discord -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    if (Wait-DiscordReadyForInitialPatch) {
        Write-Host "Patching Discord with official Vencord CLI..."
        Write-SetupLog "Initial patch started"
        $result = Invoke-VencordInstallerCli -InstallerPath $installerPath -DiscordRoot $discordRoot
        $output = $result.Output
        $exitCode = $result.ExitCode

        if ($output) {
            $output | ForEach-Object { Write-SetupLog "CLI: $_" }
        }

        if ($exitCode -ne 0) {
            Write-Warning "Initial patch failed. Watchdog will retry when Discord is ready."
            Write-SetupLog "Initial patch failed with exit code $exitCode"
        } else {
            Write-SetupLog "Initial patch finished"
        }
    } else {
        Write-Warning "Discord looks busy or incomplete. Watchdog will patch it automatically when it is ready."
        Write-SetupLog "Initial patch postponed because Discord was not ready"
    }
} else {
    Write-Warning "Discord folder was not found. Watchdog will wait until Discord is installed."
    Write-SetupLog "Discord folder not found during setup"
}

Install-Task -TaskName $taskName -ScriptPath $watchdogPath
Write-SetupLog "Task installed"

Write-Host ""
Write-Host "AutoVencord installed successfully." -ForegroundColor Green
Write-Host "Folder: $baseDir"
Write-Host "Task:   $taskName"
Write-Host ""
