$ErrorActionPreference = "SilentlyContinue"

$baseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$installer = Join-Path $baseDir "VencordInstallerCli.exe"
$discordRoot = Join-Path $env:LOCALAPPDATA "Discord"
$logPath = Join-Path $baseDir "last-action.log"
$logMaxBytes = 2097152
$debounceSeconds = 5
$retryDelaySeconds = 10
$maxReadyWaitSeconds = 300
$patchTimeoutSeconds = 180
$periodicCheckSeconds = 1800
$script:isChecking = $false
$mutexName = "Local\AutoVencordWatchdog-$($env:USERNAME)"
$mutexCreated = $false
$mutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$mutexCreated)

if (-not $mutexCreated) {
    exit 0
}

function Rotate-LogIfNeeded {
    try {
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
    } catch {}
}

function Write-Log($message) {
    try {
        New-Item -ItemType Directory -Force -Path $baseDir | Out-Null
        Rotate-LogIfNeeded
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -Path $logPath -Value "[$timestamp] $message"
    } catch {}
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
            $process = Start-Process -FilePath $installer -ArgumentList @("-install", "-location", $discordRoot) -PassThru -NoNewWindow -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath

            if (-not $process.WaitForExit($patchTimeoutSeconds * 1000)) {
                Write-Log "Patch timed out after $patchTimeoutSeconds seconds, stopping CLI process"
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                return $false
            }

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
    while ($true) {
        while (-not (Test-Path $discordRoot)) {
            Write-Log "Discord root missing, waiting for it to appear"
            Start-Sleep -Seconds 30
        }

        $watcher = $null

        try {
            Get-EventSubscriber -ErrorAction SilentlyContinue |
                Where-Object { $_.SourceIdentifier -like "AutoVencord.*" } |
                Unregister-Event -ErrorAction SilentlyContinue

            Get-Event -ErrorAction SilentlyContinue |
                Where-Object { $_.SourceIdentifier -like "AutoVencord.*" } |
                Remove-Event -ErrorAction SilentlyContinue

            $watcher = New-Object System.IO.FileSystemWatcher
            $watcher.Path = $discordRoot
            $watcher.IncludeSubdirectories = $true
            $watcher.InternalBufferSize = 65536
            $watcher.NotifyFilter = [System.IO.NotifyFilters]::DirectoryName -bor [System.IO.NotifyFilters]::FileName -bor [System.IO.NotifyFilters]::LastWrite -bor [System.IO.NotifyFilters]::Size
            $watcher.EnableRaisingEvents = $true

            Register-ObjectEvent -InputObject $watcher -EventName Created -SourceIdentifier "AutoVencord.Created" | Out-Null
            Register-ObjectEvent -InputObject $watcher -EventName Changed -SourceIdentifier "AutoVencord.Changed" | Out-Null
            Register-ObjectEvent -InputObject $watcher -EventName Renamed -SourceIdentifier "AutoVencord.Renamed" | Out-Null
            Register-ObjectEvent -InputObject $watcher -EventName Error -SourceIdentifier "AutoVencord.Error" | Out-Null

            Write-Log "Watcher started"
            Invoke-PatchIfNeeded

            while (Test-Path $discordRoot) {
                $event = Wait-Event -Timeout $periodicCheckSeconds

                if ($event) {
                    $sourceIdentifier = $event.SourceIdentifier
                    Start-Sleep -Seconds $debounceSeconds
                    Get-Event -ErrorAction SilentlyContinue |
                        Where-Object { $_.SourceIdentifier -like "AutoVencord.*" } |
                        Remove-Event -ErrorAction SilentlyContinue

                    if ($sourceIdentifier -eq "AutoVencord.Error") {
                        Write-Log "Watcher error detected, restarting watcher"
                        break
                    }

                    Write-Log "Discord filesystem change batch detected"
                    Invoke-PatchIfNeeded
                } else {
                    Write-Log "Periodic safety check"
                    Invoke-PatchIfNeeded
                }
            }

            Write-Log "Discord root disappeared or watcher restart requested"
        } catch {
            Write-Log "Watcher crashed: $($_.Exception.Message)"
        } finally {
            Get-EventSubscriber -ErrorAction SilentlyContinue |
                Where-Object { $_.SourceIdentifier -like "AutoVencord.*" } |
                Unregister-Event -ErrorAction SilentlyContinue

            if ($watcher) {
                $watcher.EnableRaisingEvents = $false
                $watcher.Dispose()
            }
        }

        Start-Sleep -Seconds 15
    }
}

try {
    Start-Watcher
} finally {
    if ($mutex) {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
}
