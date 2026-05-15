$script:AutoVencordPayloadVersion = "2026.05.15.4"
$script:AutoVencordExitCodes = @{
    Success = 0
    NetworkFailure = 10
    DiscordMissing = 20
    DiscordNotReady = 21
    CliDownloadFailed = 30
    PatchFailed = 40
    TaskFailed = 50
    UninstallFailed = 60
}

function Get-AutoVencordPayloadVersion {
    return $script:AutoVencordPayloadVersion
}

function Get-AutoVencordExitCodes {
    return $script:AutoVencordExitCodes
}

function Set-AutoVencordContext {
    param(
        [string]$BaseDir,
        [string]$TaskName = "AutoVencord Watchdog"
    )

    $resolvedBaseDir = if ([string]::IsNullOrWhiteSpace($BaseDir)) {
        Join-Path $env:LOCALAPPDATA "AutoVencord"
    } else {
        $BaseDir
    }

    $script:AutoVencordContext = [ordered]@{
        BaseDir = $resolvedBaseDir
        TaskName = $TaskName
        InstallerPath = Join-Path $resolvedBaseDir "VencordInstallerCli.exe"
        WatchdogPath = Join-Path $resolvedBaseDir "watchdog.ps1"
        CorePath = Join-Path $resolvedBaseDir "AutoVencord.Core.ps1"
        SetupPath = Join-Path $resolvedBaseDir "AutoVencord-Setup.ps1"
        BatchPath = Join-Path $resolvedBaseDir "AutoVencord-OneClick.bat"
        UninstallPath = Join-Path $resolvedBaseDir "uninstall.bat"
        LogPath = Join-Path $resolvedBaseDir "last-action.log"
        PreviousLogPath = Join-Path $resolvedBaseDir "last-action.previous.log"
        RuntimeManifestPath = Join-Path $resolvedBaseDir "installed-manifest.json"
        DiscordRoot = Join-Path $env:LOCALAPPDATA "Discord"
        LogMaxBytes = 2097152
        ReadyRetryDelaySeconds = 10
        ReadyMaxWaitSeconds = 300
        PatchTimeoutSeconds = 180
        PeriodicCheckSeconds = 1800
        DebounceSeconds = 5
        WatcherRestartDelaySeconds = 15
    }

    return [pscustomobject]$script:AutoVencordContext
}

function Get-AutoVencordContext {
    if (-not $script:AutoVencordContext) {
        Set-AutoVencordContext | Out-Null
    }

    return [pscustomobject]$script:AutoVencordContext
}

function Get-AutoVencordRuntimeFileNames {
    return @(
        "AutoVencord.Core.ps1",
        "AutoVencord-Setup.ps1",
        "AutoVencord-OneClick.bat",
        "watchdog.ps1",
        "uninstall.bat"
    )
}

function Get-FileSha256 {
    param(
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
    } catch {
        return $null
    }
}

function Enable-Tls12IfAvailable {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]3072
    } catch {}
}

function Read-JsonFile {
    param(
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Write-JsonFileAtomic {
    param(
        [string]$Path,
        $Object
    )

    $directory = Split-Path -Parent $Path
    if ($directory) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }

    $tempPath = "{0}.{1}.tmp" -f $Path, ([guid]::NewGuid().ToString("N"))
    try {
        $json = $Object | ConvertTo-Json -Depth 8
        [System.IO.File]::WriteAllText($tempPath, $json, [System.Text.Encoding]::UTF8)
        Move-Item -LiteralPath $tempPath -Destination $Path -Force
    } finally {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-AtomicTextWrite {
    param(
        [string]$Path,
        [string]$Content,
        [System.Text.Encoding]$Encoding
    )

    $directory = Split-Path -Parent $Path
    if ($directory) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }

    $tempPath = "{0}.{1}.tmp" -f $Path, ([guid]::NewGuid().ToString("N"))
    try {
        [System.IO.File]::WriteAllText($tempPath, $Content, $Encoding)
        Move-Item -LiteralPath $tempPath -Destination $Path -Force
    } finally {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-DownloadToFile {
    param(
        [string[]]$Urls,
        [string]$DestinationPath,
        [int]$MinBytes = 0,
        [scriptblock]$ValidationScript
    )

    Enable-Tls12IfAvailable

    $errors = @()
    $destinationDir = Split-Path -Parent $DestinationPath
    if ($destinationDir) {
        New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
    }

    foreach ($url in $Urls) {
        if ([string]::IsNullOrWhiteSpace($url)) {
            continue
        }

        $tempPath = "{0}.{1}.tmp" -f $DestinationPath, ([guid]::NewGuid().ToString("N"))

        try {
            if (Get-Command Invoke-WebRequest -ErrorAction SilentlyContinue) {
                Invoke-WebRequest -UseBasicParsing $url -OutFile $tempPath
            } else {
                $client = New-Object System.Net.WebClient
                $client.DownloadFile($url, $tempPath)
            }

            if ($MinBytes -gt 0) {
                $item = Get-Item -LiteralPath $tempPath -ErrorAction Stop
                if ($item.Length -lt $MinBytes) {
                    throw "Downloaded file is smaller than expected."
                }
            }

            if ($ValidationScript -and -not (& $ValidationScript $tempPath)) {
                throw "Downloaded file did not pass validation."
            }

            Move-Item -LiteralPath $tempPath -Destination $DestinationPath -Force
            return [pscustomobject]@{
                Success = $true
                Url = $url
                Path = $DestinationPath
                Errors = @()
            }
        } catch {
            $errors += ("{0}: {1}" -f $url, $_.Exception.Message)
        } finally {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }

    return [pscustomobject]@{
        Success = $false
        Url = $null
        Path = $DestinationPath
        Errors = $errors
    }
}

function Test-WindowsExecutable {
    param(
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    try {
        $item = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($item.Length -lt 102400) {
            return $false
        }

        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        try {
            $first = $stream.ReadByte()
            $second = $stream.ReadByte()
            return ($first -eq 0x4D -and $second -eq 0x5A)
        } finally {
            $stream.Close()
        }
    } catch {
        return $false
    }
}

function Rotate-AutoVencordLogIfNeeded {
    param(
        [string]$LogPath
    )

    $context = Get-AutoVencordContext
    if (-not (Test-Path -LiteralPath $LogPath)) {
        return
    }

    try {
        $size = (Get-Item -LiteralPath $LogPath).Length
        if ($size -lt $context.LogMaxBytes) {
            return
        }

        if (Test-Path -LiteralPath $context.PreviousLogPath) {
            Remove-Item -LiteralPath $context.PreviousLogPath -Force -ErrorAction SilentlyContinue
        }

        Move-Item -LiteralPath $LogPath -Destination $context.PreviousLogPath -Force
    } catch {}
}

function Write-AutoVencordLog {
    param(
        [string]$Phase = "RUNTIME",
        [string]$Action = "info",
        [string]$Message,
        [string]$Fingerprint,
        [Nullable[int]]$ExitCode
    )

    try {
        $context = Get-AutoVencordContext
        New-Item -ItemType Directory -Force -Path $context.BaseDir | Out-Null
        Rotate-AutoVencordLogIfNeeded -LogPath $context.LogPath

        $parts = @(
            ("phase={0}" -f $Phase),
            ("action={0}" -f $Action)
        )

        if ($Fingerprint) {
            $parts += ("fingerprint={0}" -f $Fingerprint)
        }

        if ($null -ne $ExitCode) {
            $parts += ("exit={0}" -f $ExitCode)
        }

        $parts += ("message={0}" -f $Message)
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -Path $context.LogPath -Value ("[{0}] {1}" -f $timestamp, ($parts -join " | "))
    } catch {}
}

function Invoke-SchtasksSafe {
    param(
        [string[]]$Arguments
    )

    $originalErrorActionPreference = $ErrorActionPreference
    $originalPreferenceExists = Test-Path variable:PSNativeCommandUseErrorActionPreference
    if ($originalPreferenceExists) {
        $originalPreference = $PSNativeCommandUseErrorActionPreference
    }

    try {
        $ErrorActionPreference = "Continue"
        if ($originalPreferenceExists) {
            $PSNativeCommandUseErrorActionPreference = $false
        }

        $output = & schtasks.exe @Arguments 2>&1
        return [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output = @($output)
        }
    } catch {
        return [pscustomobject]@{
            ExitCode = 1
            Output = @($_.Exception.Message)
        }
    } finally {
        $ErrorActionPreference = $originalErrorActionPreference
        if ($originalPreferenceExists) {
            $PSNativeCommandUseErrorActionPreference = $originalPreference
        }
    }
}

function Stop-AutoVencordTask {
    $context = Get-AutoVencordContext

    if (Get-Command Stop-ScheduledTask -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName $context.TaskName -ErrorAction SilentlyContinue | Out-Null
    }

    $null = Invoke-SchtasksSafe -Arguments @("/End", "/TN", $context.TaskName)
}

function Install-AutoVencordTask {
    param(
        [string]$ScriptPath
    )

    $context = Get-AutoVencordContext
    $commandArgument = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPath`""
    Stop-AutoVencordTask

    if (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $context.TaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $commandArgument
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Days 3650)

        Register-ScheduledTask -TaskName $context.TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
        try {
            Start-ScheduledTask -TaskName $context.TaskName -ErrorAction Stop
        } catch {
            Write-AutoVencordLog -Phase "SETUP" -Action "task-start" -Message $_.Exception.Message
        }

        return $true
    }

    $null = Invoke-SchtasksSafe -Arguments @("/Delete", "/TN", $context.TaskName, "/F")
    $createResult = Invoke-SchtasksSafe -Arguments @("/Create", "/F", "/SC", "ONLOGON", "/TN", $context.TaskName, "/TR", "powershell.exe $commandArgument")
    if ($createResult.ExitCode -ne 0) {
        Write-AutoVencordLog -Phase "SETUP" -Action "task-create" -Message ($createResult.Output -join " ") -ExitCode $createResult.ExitCode
        return $false
    }

    $null = Invoke-SchtasksSafe -Arguments @("/Run", "/TN", $context.TaskName)
    return $true
}

function Get-WatchdogState {
    $context = Get-AutoVencordContext
    $rawState = "Unknown"

    if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
        try {
            $task = Get-ScheduledTask -TaskName $context.TaskName -ErrorAction Stop
            $rawState = [string]$task.State
        } catch {
            $rawState = "NotInstalled"
        }
    } else {
        try {
            $query = Invoke-SchtasksSafe -Arguments @("/Query", "/TN", $context.TaskName, "/FO", "LIST")
            if ($query.ExitCode -ne 0 -or -not $query.Output) {
                $rawState = "NotInstalled"
            } else {
                $statusLine = $query.Output | Where-Object { $_ -like "Status:*" } | Select-Object -First 1
                if ($statusLine) {
                    $rawState = ($statusLine -replace "^Status:\s*", "").Trim()
                }
            }
        } catch {
            $rawState = "Unknown"
        }
    }

    $state = "WatchdogFaulted"
    switch -Regex ($rawState) {
        "^(Ready|Running)$" { $state = "WatchdogRunning"; break }
        "^NotInstalled$" { $state = "WatchdogMissing"; break }
        "^(Queued|Disabled)$" { $state = "WatchdogInstalled"; break }
        default { $state = "WatchdogFaulted"; break }
    }

    return [pscustomobject]@{
        State = $state
        RawState = $rawState
    }
}

function Get-DiscordAppVersion {
    param(
        [string]$DirectoryName
    )

    $raw = $DirectoryName -replace "^app-", ""

    try {
        return [version]$raw
    } catch {
        return [version]"0.0.0.0"
    }
}

function Get-LatestDiscordInstall {
    $context = Get-AutoVencordContext
    if (-not (Test-Path -LiteralPath $context.DiscordRoot)) {
        return $null
    }

    $latest = $null
    $latestVersion = [version]"0.0.0.0"
    $latestWriteTime = [datetime]::MinValue

    $dirs = Get-ChildItem -LiteralPath $context.DiscordRoot -ErrorAction SilentlyContinue |
        Where-Object { $_.PSIsContainer -and $_.Name -like "app-*" }

    foreach ($dir in $dirs) {
        $version = Get-DiscordAppVersion -DirectoryName $dir.Name
        if (($version -gt $latestVersion) -or ($version -eq $latestVersion -and $dir.LastWriteTimeUtc -gt $latestWriteTime)) {
            $latest = $dir
            $latestVersion = $version
            $latestWriteTime = $dir.LastWriteTimeUtc
        }
    }

    return $latest
}

function Test-DiscordUpdaterActive {
    $context = Get-AutoVencordContext
    $processes = Get-Process -ErrorAction SilentlyContinue |
        Where-Object { @("Update", "Squirrel") -contains $_.ProcessName }

    foreach ($process in $processes) {
        $path = $null

        try {
            $path = $process.Path
        } catch {}

        if ($path -and ($path.StartsWith($context.DiscordRoot, [System.StringComparison]::OrdinalIgnoreCase) -or $path -like "*\SquirrelTemp\*")) {
            return $true
        }
    }

    $squirrelTemp = Join-Path $context.DiscordRoot "SquirrelTemp"
    if (Test-Path -LiteralPath $squirrelTemp) {
        try {
            if ((Get-Item -LiteralPath $squirrelTemp).LastWriteTimeUtc -gt (Get-Date).ToUniversalTime().AddMinutes(-5)) {
                return $true
            }
        } catch {}
    }

    return $false
}

function Test-FileStable {
    param(
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    try {
        $first = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($first.Length -le 0) {
            return $false
        }

        Start-Sleep -Seconds 2

        $second = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($first.Length -ne $second.Length -or $first.LastWriteTimeUtc -ne $second.LastWriteTimeUtc) {
            return $false
        }

        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        $stream.Close()
        return $true
    } catch {
        return $false
    }
}

function Get-DiscordFingerprint {
    param(
        $AppDir
    )

    if (-not $AppDir) {
        return $null
    }

    $resources = Join-Path $AppDir.FullName "resources"
    $appAsar = Join-Path $resources "app.asar"
    $length = ""

    try {
        if (Test-Path -LiteralPath $appAsar) {
            $length = (Get-Item -LiteralPath $appAsar).Length
        }
    } catch {}

    return "{0}|{1}|{2}" -f $AppDir.Name, $AppDir.LastWriteTimeUtc.ToString("o"), $length
}

function Get-DiscordState {
    $context = Get-AutoVencordContext
    if (-not (Test-Path -LiteralPath $context.DiscordRoot)) {
        return [pscustomobject]@{
            State = "DiscordMissing"
            Message = "Discord was not found."
            Latest = $null
            Fingerprint = $null
        }
    }

    $latest = Get-LatestDiscordInstall
    if (-not $latest) {
        return [pscustomobject]@{
            State = "DiscordIncomplete"
            Message = "Discord folder exists, but no app-* version folder was found."
            Latest = $null
            Fingerprint = $null
        }
    }

    $resources = Join-Path $latest.FullName "resources"
    $appAsar = Join-Path $resources "app.asar"
    $buildInfo = Join-Path $resources "build_info.json"
    $fingerprint = Get-DiscordFingerprint -AppDir $latest

    if (-not (Test-Path -LiteralPath $resources) -or -not (Test-Path -LiteralPath $appAsar) -or -not (Test-Path -LiteralPath $buildInfo)) {
        return [pscustomobject]@{
            State = "DiscordIncomplete"
            Message = "Discord files are incomplete."
            Latest = $latest
            Fingerprint = $fingerprint
        }
    }

    if (Test-DiscordUpdaterActive) {
        return [pscustomobject]@{
            State = "DiscordUpdating"
            Message = "Discord updater is active."
            Latest = $latest
            Fingerprint = $fingerprint
        }
    }

    if (-not (Test-FileStable -Path $appAsar)) {
        return [pscustomobject]@{
            State = "DiscordUpdating"
            Message = "Discord files are still changing."
            Latest = $latest
            Fingerprint = $fingerprint
        }
    }

    return [pscustomobject]@{
        State = "DiscordReady"
        Message = "Discord is ready."
        Latest = $latest
        Fingerprint = $fingerprint
    }
}

function Wait-ForDiscordReady {
    param(
        [int]$MaxWaitSeconds = 300,
        [string]$LogPhase = "RUNTIME"
    )

    $context = Get-AutoVencordContext
    $deadline = (Get-Date).AddSeconds($MaxWaitSeconds)
    $lastState = $null

    while ((Get-Date) -lt $deadline) {
        $state = Get-DiscordState
        if ($state.State -eq "DiscordReady") {
            return $state
        }

        if ($lastState -ne $state.State) {
            Write-AutoVencordLog -Phase $LogPhase -Action "wait-discord" -Message $state.Message -Fingerprint $state.Fingerprint
            $lastState = $state.State
        }

        Start-Sleep -Seconds $context.ReadyRetryDelaySeconds
    }

    return Get-DiscordState
}

function Get-AppAsarTextSample {
    param(
        [string]$Path,
        [int]$MaxBytes = 4096
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        $item = Get-Item -LiteralPath $Path -ErrorAction Stop
        $bytesToRead = [Math]::Min($MaxBytes, [int]$item.Length)
        $buffer = New-Object byte[] $bytesToRead
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            [void]$stream.Read($buffer, 0, $bytesToRead)
        } finally {
            $stream.Close()
        }

        return [System.Text.Encoding]::UTF8.GetString($buffer)
    } catch {
        return $null
    }
}

function Get-PatchState {
    param(
        $AppDir
    )

    if (-not $AppDir) {
        return [pscustomobject]@{
            State = "PatchUnknown"
            Reason = "No Discord app directory was provided."
            Fingerprint = $null
        }
    }

    $resources = Join-Path $AppDir.FullName "resources"
    $appAsar = Join-Path $resources "app.asar"
    $backupAsar = Join-Path $resources "_app.asar"
    $fingerprint = Get-DiscordFingerprint -AppDir $AppDir

    if (-not (Test-Path -LiteralPath $appAsar)) {
        return [pscustomobject]@{
            State = "PatchUnknown"
            Reason = "app.asar is missing."
            Fingerprint = $fingerprint
        }
    }

    $appItem = Get-Item -LiteralPath $appAsar -ErrorAction SilentlyContinue
    $backupExists = Test-Path -LiteralPath $backupAsar
    $backupItem = if ($backupExists) { Get-Item -LiteralPath $backupAsar -ErrorAction SilentlyContinue } else { $null }
    $sample = Get-AppAsarTextSample -Path $appAsar
    $hasKnownMarker = $false

    if ($sample) {
        $hasKnownMarker = ($sample -match "patcher\.js" -or $sample -match "Roaming\\Vencord" -or $sample -match "vencord")
    }

    if (-not $backupExists) {
        if ($hasKnownMarker) {
            return [pscustomobject]@{
                State = "PatchUnknown"
                Reason = "Vencord markers were found without a backup _app.asar."
                Fingerprint = $fingerprint
            }
        }

        return [pscustomobject]@{
            State = "PatchMissing"
            Reason = "Backup _app.asar is missing."
            Fingerprint = $fingerprint
        }
    }

    $smallStub = $false
    $significantDelta = $false
    if ($appItem -and $backupItem) {
        $smallStub = ($appItem.Length -lt 32768 -and $backupItem.Length -gt ($appItem.Length * 2))
        $significantDelta = ($appItem.Length -ne $backupItem.Length -or $appItem.LastWriteTimeUtc -ne $backupItem.LastWriteTimeUtc)
    }

    if ($smallStub -or $hasKnownMarker) {
        return [pscustomobject]@{
            State = "PatchPresent"
            Reason = "Known Vencord patch markers were found."
            Fingerprint = $fingerprint
        }
    }

    if ($significantDelta) {
        return [pscustomobject]@{
            State = "PatchUnknown"
            Reason = "Backup exists, but the patch signature is inconclusive."
            Fingerprint = $fingerprint
        }
    }

    return [pscustomobject]@{
        State = "PatchUnknown"
        Reason = "Backup exists, but patch state could not be determined safely."
        Fingerprint = $fingerprint
    }
}

function Invoke-VencordCliAction {
    param(
        [string]$InstallerPath,
        [ValidateSet("install", "uninstall")] [string]$Action,
        [string]$DiscordRoot,
        [int]$TimeoutSeconds = 180,
        [string]$LogPhase = "RUNTIME"
    )

    $context = Get-AutoVencordContext
    $stdoutPath = Join-Path $context.BaseDir ("cli-stdout-" + [guid]::NewGuid().ToString("N") + ".log")
    $stderrPath = Join-Path $context.BaseDir ("cli-stderr-" + [guid]::NewGuid().ToString("N") + ".log")
    $output = @()
    $timedOut = $false
    $exitCode = 1

    try {
        $process = Start-Process -FilePath $InstallerPath -ArgumentList @("-$Action", "-location", $DiscordRoot) -PassThru -NoNewWindow -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $timedOut = $true
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            $exitCode = 124
        } else {
            $exitCode = $process.ExitCode
        }
    } catch {
        $output += $_.Exception.Message
        $exitCode = 1
    } finally {
        if (Test-Path -LiteralPath $stdoutPath) {
            $output += Get-Content -LiteralPath $stdoutPath -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue
        }

        if (Test-Path -LiteralPath $stderrPath) {
            $output += Get-Content -LiteralPath $stderrPath -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
        }
    }

    if ($output) {
        foreach ($line in $output) {
            Write-AutoVencordLog -Phase $LogPhase -Action ("cli-" + $Action) -Message ("CLI: " + $line)
        }
    }

    $outputText = ($output -join "`n")
    $reportedSuccess = $false
    if ($Action -eq "install") {
        $reportedSuccess = ($outputText -match "Success" -or $outputText -match "Successfully patched")
    } else {
        $reportedSuccess = ($outputText -match "Success" -or $outputText -match "Successfully unpatched")
    }

    return [pscustomobject]@{
        Success = (-not $timedOut -and ($exitCode -eq 0 -or $reportedSuccess))
        ExitCode = $exitCode
        TimedOut = $timedOut
        Output = @($output)
    }
}

function Get-InstalledPayloadManifest {
    $context = Get-AutoVencordContext
    return Read-JsonFile -Path $context.RuntimeManifestPath
}

function Write-InstalledPayloadManifest {
    param(
        [string]$PayloadVersion,
        [string]$PayloadRef,
        [hashtable]$FileHashes
    )

    $manifest = [ordered]@{
        version = $PayloadVersion
        payloadRef = $PayloadRef
        installedAt = (Get-Date).ToString("o")
        files = $FileHashes
    }

    $context = Get-AutoVencordContext
    Write-JsonFileAtomic -Path $context.RuntimeManifestPath -Object $manifest
}

function Get-AutoVencordStatus {
    $context = Get-AutoVencordContext
    $discord = Get-DiscordState
    $manifest = Get-InstalledPayloadManifest

    $runtimeFiles = @($context.CorePath, $context.SetupPath, $context.WatchdogPath, $context.UninstallPath, $context.BatchPath)
    $hasRuntimeFiles = (($runtimeFiles | Where-Object { Test-Path -LiteralPath $_ }).Count -gt 0)
    $hasInstaller = Test-Path -LiteralPath $context.InstallerPath
    $isInstalled = $hasRuntimeFiles -and ($hasInstaller -or $manifest)
    $watchdog = if ($isInstalled) {
        Get-WatchdogState
    } else {
        [pscustomobject]@{
            State = "WatchdogMissing"
            RawState = "NotInstalled"
        }
    }

    return [pscustomobject]@{
        Installed = [bool]$isInstalled
        Watchdog = $watchdog
        Discord = $discord
        Manifest = $manifest
    }
}

function Test-RelevantDiscordPath {
    param(
        [string]$Path
    )

    if (-not $Path) {
        return $false
    }

    return ($Path -like "*\app-*\*" -or $Path -like "*\SquirrelTemp\*" -or $Path -like "*\Discord\app-*")
}

function Start-AutoVencordWatchdogLoop {
    $context = Get-AutoVencordContext
    $mutexName = "Local\AutoVencordWatchdog-$($env:USERNAME)"
    $mutexCreated = $false
    $mutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$mutexCreated)

    if (-not $mutexCreated) {
        return
    }

    $isChecking = $false
    $lastSuccessfulFingerprint = $null
    $lastAttemptFingerprint = $null
    $lastAttemptAt = [datetime]::MinValue
    $restartDelay = $context.WatcherRestartDelaySeconds

    function Invoke-PatchCheck {
        if ($isChecking) {
            Write-AutoVencordLog -Phase "WATCHDOG" -Action "skip" -Message "Check skipped because another check is already running."
            return
        }

        $script:isChecking = $true
        $isChecking = $true

        try {
            $discordState = Get-DiscordState

            if ($discordState.State -ne "DiscordReady") {
                Write-AutoVencordLog -Phase "WATCHDOG" -Action "discord-state" -Message $discordState.Message -Fingerprint $discordState.Fingerprint
                return
            }

            $patchState = Get-PatchState -AppDir $discordState.Latest
            switch ($patchState.State) {
                "PatchPresent" {
                    $lastSuccessfulFingerprint = $patchState.Fingerprint
                    Write-AutoVencordLog -Phase "WATCHDOG" -Action "patch-state" -Message "Discord is already patched." -Fingerprint $patchState.Fingerprint
                    return
                }
                "PatchUnknown" {
                    Write-AutoVencordLog -Phase "WATCHDOG" -Action "patch-state" -Message $patchState.Reason -Fingerprint $patchState.Fingerprint
                    return
                }
            }

            if ($lastSuccessfulFingerprint -eq $patchState.Fingerprint) {
                return
            }

            if ($lastAttemptFingerprint -eq $patchState.Fingerprint -and ((Get-Date) -lt $lastAttemptAt.AddSeconds(30))) {
                return
            }

            $lastAttemptFingerprint = $patchState.Fingerprint
            $lastAttemptAt = Get-Date

            $readyState = Wait-ForDiscordReady -MaxWaitSeconds $context.ReadyMaxWaitSeconds -LogPhase "WATCHDOG"
            if ($readyState.State -ne "DiscordReady") {
                Write-AutoVencordLog -Phase "WATCHDOG" -Action "patch-postpone" -Message $readyState.Message -Fingerprint $readyState.Fingerprint
                return
            }

            $recheckPatch = Get-PatchState -AppDir $readyState.Latest
            if ($recheckPatch.State -eq "PatchPresent") {
                $lastSuccessfulFingerprint = $recheckPatch.Fingerprint
                return
            }

            if ($recheckPatch.State -eq "PatchUnknown") {
                Write-AutoVencordLog -Phase "WATCHDOG" -Action "patch-state" -Message $recheckPatch.Reason -Fingerprint $recheckPatch.Fingerprint
                return
            }

            Write-AutoVencordLog -Phase "WATCHDOG" -Action "patch-start" -Message "Starting patch for Discord." -Fingerprint $recheckPatch.Fingerprint
            $result = Invoke-VencordCliAction -InstallerPath $context.InstallerPath -Action "install" -DiscordRoot $context.DiscordRoot -TimeoutSeconds $context.PatchTimeoutSeconds -LogPhase "WATCHDOG"
            if (-not $result.Success) {
                Write-AutoVencordLog -Phase "WATCHDOG" -Action "patch-failed" -Message "Patch command failed." -Fingerprint $recheckPatch.Fingerprint -ExitCode $result.ExitCode
                return
            }

            Start-Sleep -Seconds 2
            $verifiedDiscordState = Get-DiscordState
            $verifiedPatchState = Get-PatchState -AppDir $verifiedDiscordState.Latest
            if ($verifiedPatchState.State -eq "PatchPresent") {
                $lastSuccessfulFingerprint = $verifiedPatchState.Fingerprint
                Write-AutoVencordLog -Phase "WATCHDOG" -Action "patch-verified" -Message "Patch verified successfully." -Fingerprint $verifiedPatchState.Fingerprint
            } else {
                Write-AutoVencordLog -Phase "WATCHDOG" -Action "patch-verify-failed" -Message $verifiedPatchState.Reason -Fingerprint $verifiedPatchState.Fingerprint
            }
        } finally {
            $script:isChecking = $false
            $isChecking = $false
        }
    }

    try {
        while ($true) {
            while (-not (Test-Path -LiteralPath $context.DiscordRoot)) {
                Write-AutoVencordLog -Phase "WATCHDOG" -Action "wait-root" -Message "Discord root missing, waiting for it to appear."
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
                $watcher.Path = $context.DiscordRoot
                $watcher.IncludeSubdirectories = $true
                $watcher.InternalBufferSize = 65536
                $watcher.NotifyFilter = [System.IO.NotifyFilters]::DirectoryName -bor [System.IO.NotifyFilters]::FileName -bor [System.IO.NotifyFilters]::LastWrite -bor [System.IO.NotifyFilters]::Size
                $watcher.EnableRaisingEvents = $true

                Register-ObjectEvent -InputObject $watcher -EventName Created -SourceIdentifier "AutoVencord.Created" | Out-Null
                Register-ObjectEvent -InputObject $watcher -EventName Changed -SourceIdentifier "AutoVencord.Changed" | Out-Null
                Register-ObjectEvent -InputObject $watcher -EventName Renamed -SourceIdentifier "AutoVencord.Renamed" | Out-Null
                Register-ObjectEvent -InputObject $watcher -EventName Error -SourceIdentifier "AutoVencord.Error" | Out-Null

                Write-AutoVencordLog -Phase "WATCHDOG" -Action "watcher-start" -Message "Watcher started."
                Invoke-PatchCheck

                while (Test-Path -LiteralPath $context.DiscordRoot) {
                    $event = Wait-Event -Timeout $context.PeriodicCheckSeconds
                    if ($event) {
                        $sourceIdentifier = $event.SourceIdentifier
                        $eventPath = $null
                        try {
                            $eventPath = $event.SourceEventArgs.FullPath
                        } catch {}

                        Start-Sleep -Seconds $context.DebounceSeconds
                        Get-Event -ErrorAction SilentlyContinue |
                            Where-Object { $_.SourceIdentifier -like "AutoVencord.*" } |
                            Remove-Event -ErrorAction SilentlyContinue

                        if ($sourceIdentifier -eq "AutoVencord.Error") {
                            Write-AutoVencordLog -Phase "WATCHDOG" -Action "watcher-error" -Message "Watcher error detected, restarting."
                            break
                        }

                        if (Test-RelevantDiscordPath -Path $eventPath) {
                            Write-AutoVencordLog -Phase "WATCHDOG" -Action "filesystem-change" -Message "Relevant Discord filesystem change detected." -Fingerprint $eventPath
                            Invoke-PatchCheck
                        }
                    } else {
                        Write-AutoVencordLog -Phase "WATCHDOG" -Action "periodic-check" -Message "Running periodic safety check."
                        Invoke-PatchCheck
                    }
                }
            } catch {
                Write-AutoVencordLog -Phase "WATCHDOG" -Action "watcher-crash" -Message $_.Exception.Message
            } finally {
                Get-EventSubscriber -ErrorAction SilentlyContinue |
                    Where-Object { $_.SourceIdentifier -like "AutoVencord.*" } |
                    Unregister-Event -ErrorAction SilentlyContinue

                if ($watcher) {
                    $watcher.EnableRaisingEvents = $false
                    $watcher.Dispose()
                }
            }

            Start-Sleep -Seconds $restartDelay
            $restartDelay = [Math]::Min($restartDelay * 2, 120)
        }
    } finally {
        if ($mutex) {
            $mutex.ReleaseMutex()
            $mutex.Dispose()
        }
    }
}
