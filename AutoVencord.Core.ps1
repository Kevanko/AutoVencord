$script:AutoVencordPayloadVersion = "2026.05.18.8"
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

    $resolvedDiscordRoot = Resolve-AutoVencordDiscordRoot -BaseDir $resolvedBaseDir

    $script:AutoVencordContext = [ordered]@{
        BaseDir = $resolvedBaseDir
        TaskName = $TaskName
        InstallerPath = Join-Path $resolvedBaseDir "VencordInstallerCli.exe"
        WatchdogPath = Join-Path $resolvedBaseDir "watchdog.ps1"
        CorePath = Join-Path $resolvedBaseDir "AutoVencord.Core.ps1"
        SetupPath = Join-Path $resolvedBaseDir "AutoVencord-Setup.ps1"
        BatchPath = Join-Path $resolvedBaseDir "AutoVencord-OneClick.bat"
        PayloadManifestPath = Join-Path $resolvedBaseDir "AutoVencord-Payload.json"
        UninstallPath = Join-Path $resolvedBaseDir "uninstall.bat"
        LogPath = Join-Path $resolvedBaseDir "last-action.log"
        PreviousLogPath = Join-Path $resolvedBaseDir "last-action.previous.log"
        RuntimeManifestPath = Join-Path $resolvedBaseDir "installed-manifest.json"
        DiscordRoot = $resolvedDiscordRoot
        LogMaxBytes = 2097152
        ReadyRetryDelaySeconds = 2
        ReadyMaxWaitSeconds = 300
        PatchTimeoutSeconds = 180
        PeriodicCheckSeconds = 21600
        DebounceSeconds = 5
        PostPatchWatchSeconds = 15
        PostPatchCheckIntervalSeconds = 3
        WatcherRestartDelaySeconds = 15
        UpdaterTempGraceSeconds = 15
    }

    return [pscustomobject]$script:AutoVencordContext
}

function Set-AutoVencordDiscordRoot {
    param(
        [string]$DiscordRoot
    )

    if (-not $script:AutoVencordContext -or [string]::IsNullOrWhiteSpace($DiscordRoot)) {
        return
    }

    $resolvedRoot = Resolve-NormalizedPath -Path $DiscordRoot
    if ([string]::IsNullOrWhiteSpace($resolvedRoot)) {
        return
    }

    if ([string]$script:AutoVencordContext.DiscordRoot -ne $resolvedRoot) {
        $script:AutoVencordContext.DiscordRoot = $resolvedRoot
        Write-AutoVencordLog -Phase "RUNTIME" -Action "discord-root" -Message ("Discord root set to {0}" -f $resolvedRoot)
    }
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
        "AutoVencord-Payload.json",
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
                Invoke-WebRequest -UseBasicParsing $url -OutFile $tempPath -TimeoutSec 15
            } else {
                $client = New-Object System.Net.WebClient
                $client.Headers.Add("user-agent", "AutoVencord")
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

function Get-AutoVencordCurrentUserId {
    try {
        $identityName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        if (-not [string]::IsNullOrWhiteSpace($identityName)) {
            return $identityName
        }
    } catch {}

    if (-not [string]::IsNullOrWhiteSpace($env:USERDOMAIN) -and -not [string]::IsNullOrWhiteSpace($env:USERNAME)) {
        return ("{0}\{1}" -f $env:USERDOMAIN, $env:USERNAME)
    }

    return $env:USERNAME
}

function Install-AutoVencordTask {
    param(
        [string]$ScriptPath
    )

    $context = Get-AutoVencordContext
    $commandArgument = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPath`""
    $currentUserId = Get-AutoVencordCurrentUserId
    Stop-AutoVencordTask

    if (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue) {
        try {
            Unregister-ScheduledTask -TaskName $context.TaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

            $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $commandArgument
            $trigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUserId
            $principal = New-ScheduledTaskPrincipal -UserId $currentUserId -LogonType Interactive -RunLevel Limited
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Days 3650)

            Register-ScheduledTask -TaskName $context.TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
            try {
                Start-ScheduledTask -TaskName $context.TaskName -ErrorAction Stop
            } catch {
                Write-AutoVencordLog -Phase "SETUP" -Action "task-start" -Message $_.Exception.Message
            }

            return $true
        } catch {
            Write-AutoVencordLog -Phase "SETUP" -Action "task-register" -Message $_.Exception.Message
        }
    }

    $null = Invoke-SchtasksSafe -Arguments @("/Delete", "/TN", $context.TaskName, "/F")
    $createResult = Invoke-SchtasksSafe -Arguments @("/Create", "/F", "/SC", "ONLOGON", "/TN", $context.TaskName, "/TR", "powershell.exe $commandArgument")
    if ($createResult.ExitCode -ne 0) {
        Write-AutoVencordLog -Phase "SETUP" -Action "task-create" -Message ($createResult.Output -join " ") -ExitCode $createResult.ExitCode
        if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
            try {
                $existingTask = Get-ScheduledTask -TaskName $context.TaskName -ErrorAction Stop
                if ($existingTask) {
                    Start-ScheduledTask -TaskName $context.TaskName -ErrorAction Stop
                    Write-AutoVencordLog -Phase "SETUP" -Action "task-reuse" -Message "Existing watchdog task reused after registration failed."
                    return $true
                }
            } catch {
                Write-AutoVencordLog -Phase "SETUP" -Action "task-reuse" -Message $_.Exception.Message
            }
        }

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

function Resolve-NormalizedPath {
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    try {
        return [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path.Trim('"')))
    } catch {
        return $null
    }
}

function Resolve-DiscordRootFromPath {
    param(
        [string]$Path
    )

    $normalized = Resolve-NormalizedPath -Path $Path
    if (-not $normalized) {
        return $null
    }

    try {
        if ([System.IO.File]::Exists($normalized)) {
            $fileName = [System.IO.Path]::GetFileName($normalized)
            $parent = Split-Path -Parent $normalized

            if ($fileName -ieq "Update.exe") {
                return $parent
            }

            if ($fileName -ieq "Discord.exe") {
                $appDir = Split-Path -Parent $normalized
                if ((Split-Path -Leaf $appDir) -like "app-*") {
                    return (Split-Path -Parent $appDir)
                }
            }

            return $parent
        }

        if ([System.IO.Directory]::Exists($normalized)) {
            if ((Split-Path -Leaf $normalized) -like "app-*") {
                return (Split-Path -Parent $normalized)
            }

            return $normalized
        }
    } catch {}

    return $null
}

function Test-DiscordRootCandidate {
    param(
        [string]$Path
    )

    $root = Resolve-DiscordRootFromPath -Path $Path
    if (-not $root -or -not (Test-Path -LiteralPath $root)) {
        return $false
    }

    $updatePath = Join-Path $root "Update.exe"
    $appDir = Get-ChildItem -LiteralPath $root -Directory -Filter "app-*" -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "Discord.exe") } |
        Select-Object -First 1

    return (($null -ne $appDir) -or ((Split-Path -Leaf $root) -ieq "Discord" -and (Test-Path -LiteralPath $updatePath)))
}

function Add-DiscordRootCandidate {
    param(
        [System.Collections.Generic.List[string]]$Candidates,
        [string]$Path
    )

    $root = Resolve-DiscordRootFromPath -Path $Path
    if (-not $root) {
        return
    }

    foreach ($candidate in $Candidates) {
        if ([string]::Equals($candidate, $root, [System.StringComparison]::OrdinalIgnoreCase)) {
            return
        }
    }

    $Candidates.Add($root) | Out-Null
}

function Add-DiscordShortcutCandidates {
    param(
        [System.Collections.Generic.List[string]]$Candidates
    )

    try {
        $shell = New-Object -ComObject WScript.Shell
    } catch {
        return
    }

    $shortcutRoots = @()
    foreach ($folder in @("Desktop", "CommonDesktopDirectory", "StartMenu", "CommonStartMenu", "Programs", "CommonPrograms")) {
        try {
            $path = [Environment]::GetFolderPath($folder)
            if ($path -and (Test-Path -LiteralPath $path)) {
                $shortcutRoots += $path
            }
        } catch {}
    }

    foreach ($root in ($shortcutRoots | Select-Object -Unique)) {
        Get-ChildItem -LiteralPath $root -Filter "*.lnk" -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "*Discord*" } |
            ForEach-Object {
                try {
                    $shortcut = $shell.CreateShortcut($_.FullName)
                    Add-DiscordRootCandidate -Candidates $Candidates -Path $shortcut.TargetPath
                    Add-DiscordRootCandidate -Candidates $Candidates -Path $shortcut.WorkingDirectory
                } catch {}
            }
    }
}

function Add-InstalledManifestDiscordRootCandidate {
    param(
        [System.Collections.Generic.List[string]]$Candidates,
        [string]$BaseDir
    )

    if ([string]::IsNullOrWhiteSpace($BaseDir)) {
        return
    }

    $manifestPath = Join-Path $BaseDir "installed-manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        return
    }

    try {
        $manifest = Read-JsonFile -Path $manifestPath
        if ($manifest -and $manifest.discordRoot) {
            Add-DiscordRootCandidate -Candidates $Candidates -Path ([string]$manifest.discordRoot)
        }
    } catch {}
}

function Get-DiscordRootCandidates {
    param(
        [string]$BaseDir
    )

    $candidates = New-Object 'System.Collections.Generic.List[string]'

    Add-DiscordRootCandidate -Candidates $candidates -Path $env:AUTOVENCORD_DISCORD_ROOT
    Add-InstalledManifestDiscordRootCandidate -Candidates $candidates -BaseDir $BaseDir
    Add-DiscordRootCandidate -Candidates $candidates -Path (Join-Path $env:LOCALAPPDATA "Discord")

    Get-Process Discord,Update -ErrorAction SilentlyContinue |
        ForEach-Object {
            try {
                Add-DiscordRootCandidate -Candidates $candidates -Path $_.Path
            } catch {}
        }

    Add-DiscordShortcutCandidates -Candidates $candidates
    return @($candidates)
}

function Resolve-AutoVencordDiscordRoot {
    param(
        [string]$BaseDir
    )

    $fallback = Join-Path $env:LOCALAPPDATA "Discord"
    foreach ($candidate in Get-DiscordRootCandidates -BaseDir $BaseDir) {
        if (Test-DiscordRootCandidate -Path $candidate) {
            return (Resolve-DiscordRootFromPath -Path $candidate)
        }
    }

    return $fallback
}

function Update-AutoVencordDiscordRoot {
    $context = Get-AutoVencordContext
    if (Test-DiscordRootCandidate -Path $context.DiscordRoot) {
        return $context.DiscordRoot
    }

    $resolvedRoot = Resolve-AutoVencordDiscordRoot -BaseDir $context.BaseDir
    if ($resolvedRoot -and (Test-DiscordRootCandidate -Path $resolvedRoot)) {
        Set-AutoVencordDiscordRoot -DiscordRoot $resolvedRoot
        return $resolvedRoot
    }

    return $context.DiscordRoot
}

function Get-LatestDiscordInstall {
    param(
        [switch]$RequireComplete
    )

    $discordRoot = Update-AutoVencordDiscordRoot
    if (-not (Test-Path -LiteralPath $discordRoot)) {
        return $null
    }

    $dirs = @(Get-ChildItem -LiteralPath $discordRoot -Directory -Filter "app-*" -ErrorAction SilentlyContinue |
        Sort-Object @{ Expression = { Get-DiscordAppVersion -DirectoryName $_.Name }; Descending = $true }, @{ Expression = { $_.LastWriteTimeUtc }; Descending = $true })

    foreach ($dir in $dirs) {
        if ($RequireComplete -and -not (Test-DiscordAppInstallComplete -AppDir $dir)) {
            continue
        }

        return $dir
    }

    return $null
}

function Test-DiscordAppInstallComplete {
    param(
        $AppDir
    )

    if (-not $AppDir) {
        return $false
    }

    $discordExe = Join-Path $AppDir.FullName "Discord.exe"
    $resources = Join-Path $AppDir.FullName "resources"
    $appAsar = Join-Path $resources "app.asar"
    $buildInfo = Join-Path $resources "build_info.json"

    return (
        (Test-Path -LiteralPath $discordExe) -and
        (Test-Path -LiteralPath $resources) -and
        (Test-Path -LiteralPath $appAsar) -and
        (Test-Path -LiteralPath $buildInfo)
    )
}

function Get-DiscordClientProcesses {
    param(
        [string]$DiscordRoot
    )

    $root = if ([string]::IsNullOrWhiteSpace($DiscordRoot)) {
        Update-AutoVencordDiscordRoot
    } else {
        $DiscordRoot
    }

    return @(Get-Process Discord -ErrorAction SilentlyContinue | Where-Object {
        try {
            $_.Path -and $_.Path.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)
        } catch {
            $false
        }
    })
}

function Test-DiscordClientRunning {
    param(
        [string]$DiscordRoot
    )

    return ((Get-DiscordClientProcesses -DiscordRoot $DiscordRoot).Count -gt 0)
}

function Start-DiscordClient {
    param(
        [string]$DiscordRoot,
        [string]$LogPhase = "RUNTIME"
    )

    $root = if ([string]::IsNullOrWhiteSpace($DiscordRoot)) { Update-AutoVencordDiscordRoot } else { $DiscordRoot }
    $updatePath = Join-Path $root "Update.exe"

    try {
        if (Test-Path -LiteralPath $updatePath) {
            Start-Process -FilePath $updatePath -ArgumentList @("--processStart", "Discord.exe") | Out-Null
            Write-AutoVencordLog -Phase $LogPhase -Action "discord-restart" -Message "Discord restart requested through Update.exe."
            return $true
        }

        $latest = Get-LatestDiscordInstall
        if ($latest) {
            $discordExe = Join-Path $latest.FullName "Discord.exe"
            if (Test-Path -LiteralPath $discordExe) {
                Start-Process -FilePath $discordExe | Out-Null
                Write-AutoVencordLog -Phase $LogPhase -Action "discord-restart" -Message "Discord restart requested through Discord.exe."
                return $true
            }
        }
    } catch {
        Write-AutoVencordLog -Phase $LogPhase -Action "discord-restart-failed" -Message $_.Exception.Message
        return $false
    }

    Write-AutoVencordLog -Phase $LogPhase -Action "discord-restart-failed" -Message "Discord executable was not found."
    return $false
}

function Resume-DiscordAfterPatchIfNeeded {
    param(
        [bool]$WasRunning,
        [string]$DiscordRoot,
        [string]$LogPhase = "RUNTIME"
    )

    if (-not $WasRunning) {
        return
    }

    Start-Sleep -Seconds 1
    if (Test-DiscordClientRunning -DiscordRoot $DiscordRoot) {
        Write-AutoVencordLog -Phase $LogPhase -Action "discord-restart-skip" -Message "Discord is already running after patch."
        return
    }

    $null = Start-DiscordClient -DiscordRoot $DiscordRoot -LogPhase $LogPhase
}

function Test-DiscordUpdaterActive {
    param(
        [switch]$IncludeLog
    )

    $discordRoot = Update-AutoVencordDiscordRoot

    try {
        $processes = @(Get-CimInstance Win32_Process -Filter "Name = 'Update.exe' OR Name = 'Squirrel.exe'" -ErrorAction Stop)

        foreach ($process in $processes) {
            if (Test-DiscordUpdaterProcessActive -Name $process.Name -Path $process.ExecutablePath -CommandLine $process.CommandLine -DiscordRoot $discordRoot) {
                return $true
            }
        }
    } catch {
        $processes = Get-Process -ErrorAction SilentlyContinue |
            Where-Object { @("Update", "Squirrel") -contains $_.ProcessName }

        foreach ($process in $processes) {
            $path = $null
            try {
                $path = $process.Path
            } catch {}

            if (Test-DiscordUpdaterProcessActive -Name $process.ProcessName -Path $path -CommandLine $null -DiscordRoot $discordRoot) {
                return $true
            }
        }
    }

    $context = Get-AutoVencordContext
    $squirrelTemp = Join-Path $discordRoot "SquirrelTemp"
    if (Test-Path -LiteralPath $squirrelTemp) {
        try {
            if ((Get-Item -LiteralPath $squirrelTemp).LastWriteTimeUtc -gt (Get-Date).ToUniversalTime().AddSeconds(-[Math]::Max(1, $context.UpdaterTempGraceSeconds))) {
                return $true
            }
        } catch {}
    }

    if ($IncludeLog -and (Test-DiscordUpdaterLogActive)) {
        return $true
    }

    return $false
}

function Test-DiscordUpdaterProcessActive {
    param(
        [string]$Name,
        [string]$Path,
        [string]$CommandLine,
        [string]$DiscordRoot
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    if ($Path -like "*\SquirrelTemp\*") {
        return $true
    }

    if (-not $Path.StartsWith($DiscordRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }

    if ($Name -ieq "Squirrel.exe" -or $Name -ieq "Squirrel") {
        return $true
    }

    $command = [string]$CommandLine
    if ($command -match "(?i)--processStart(?:AndWait)?\b") {
        return $false
    }

    if ($command -match "(?i)--(?:update|install|download|checkForUpdate)\b") {
        return $true
    }

    return $false
}

function Get-DiscordUpdaterLogPath {
    $candidates = @(
        (Join-Path $env:APPDATA "discord\logs\Discord_updater_rCURRENT.log"),
        (Join-Path $env:APPDATA "Discord\logs\Discord_updater_rCURRENT.log")
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    return $null
}

function Read-TextFileTail {
    param(
        [string]$Path,
        [int]$MaxBytes = 32768
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $bytesToRead = [Math]::Min($MaxBytes, [int]$stream.Length)
            $buffer = New-Object byte[] $bytesToRead
            $stream.Seek(-$bytesToRead, [System.IO.SeekOrigin]::End) | Out-Null
            [void]$stream.Read($buffer, 0, $bytesToRead)
            return [System.Text.Encoding]::UTF8.GetString($buffer)
        } finally {
            $stream.Close()
        }
    } catch {
        return $null
    }
}

function Test-DiscordUpdaterLogActive {
    $logPath = Get-DiscordUpdaterLogPath
    if (-not $logPath) {
        return $false
    }

    try {
        $context = Get-AutoVencordContext
        $maxAgeSeconds = [Math]::Max(300, $context.ReadyMaxWaitSeconds)
        if ((Get-Item -LiteralPath $logPath).LastWriteTimeUtc -lt (Get-Date).ToUniversalTime().AddSeconds(-$maxAgeSeconds)) {
            return $false
        }
    } catch {
        return $false
    }

    $text = Read-TextFileTail -Path $logPath
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $false
    }

    $lastStart = $text.LastIndexOf("Starting update to latest.", [System.StringComparison]::OrdinalIgnoreCase)
    if ($lastStart -lt 0) {
        return $false
    }

    $lastComplete = -1
    foreach ($marker in @("Update to latest complete.", "Already up to date. Nothing to do.", "Updater main thread exiting")) {
        $index = $text.LastIndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase)
        if ($index -gt $lastComplete) {
            $lastComplete = $index
        }
    }

    return ($lastStart -gt $lastComplete)
}

function Test-FileStable {
    param(
        [string]$Path,
        [switch]$SkipWait
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    try {
        $first = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($first.Length -le 0) {
            return $false
        }

        if ($SkipWait) {
            return $true
        }

        if (-not $SkipWait) {
            Start-Sleep -Seconds 2
        }

        $second = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($first.Length -ne $second.Length -or $first.LastWriteTimeUtc -ne $second.LastWriteTimeUtc) {
            return $false
        }

        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
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
    param(
        [switch]$SkipStabilityWait
    )

    $discordRoot = Update-AutoVencordDiscordRoot
    if (-not (Test-Path -LiteralPath $discordRoot)) {
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

    $fingerprint = Get-DiscordFingerprint -AppDir $latest

    if (-not (Test-DiscordAppInstallComplete -AppDir $latest)) {
        if (Test-DiscordUpdaterActive) {
            return [pscustomobject]@{
                State = "DiscordUpdating"
                Message = "Discord updater is active."
                Latest = $latest
                Fingerprint = $fingerprint
            }
        }

        $completeLatest = Get-LatestDiscordInstall -RequireComplete
        if ($completeLatest) {
            $latest = $completeLatest
            $fingerprint = Get-DiscordFingerprint -AppDir $latest
        } elseif (Test-DiscordUpdaterLogActive) {
            return [pscustomobject]@{
                State = "DiscordUpdating"
                Message = "Discord updater log looks active."
                Latest = $latest
                Fingerprint = $fingerprint
            }
        } else {
            return [pscustomobject]@{
                State = "DiscordIncomplete"
                Message = "Discord files are incomplete."
                Latest = $latest
                Fingerprint = $fingerprint
            }
        }
    }

    $resources = Join-Path $latest.FullName "resources"
    $appAsar = Join-Path $resources "app.asar"

    if (-not (Test-Path -LiteralPath $appAsar)) {
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

    if (-not (Test-FileStable -Path $appAsar -SkipWait:$SkipStabilityWait)) {
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

function Read-NativeOutputLines {
    param(
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return @()
    }

    try {
        $utf8Strict = New-Object System.Text.UTF8Encoding $false, $true
        $text = [System.IO.File]::ReadAllText($Path, $utf8Strict)
    } catch {
        try {
            $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::Default)
        } catch {
            return @()
        }
    }

    if ([string]::IsNullOrEmpty($text)) {
        return @()
    }

    $escape = [string][char]27
    $text = $text -replace ([regex]::Escape($escape) + "\[[0-?]*[ -/]*[@-~]"), ""
    return @($text -split "\r?\n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
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

function Wait-ForDiscordFilesystemQuiet {
    param(
        [int]$QuietSeconds = 10,
        [int]$MaxWaitSeconds = 90,
        [string]$LogPhase = "RUNTIME"
    )

    $context = Get-AutoVencordContext
    $deadline = (Get-Date).AddSeconds($MaxWaitSeconds)
    $lastFingerprint = $null
    $stableSince = $null

    while ((Get-Date) -lt $deadline) {
        $state = Get-DiscordState -SkipStabilityWait
        $fingerprint = [string]$state.Fingerprint

        if ($state.State -eq "DiscordReady") {
            if ($fingerprint -eq $lastFingerprint) {
                if (-not $stableSince) {
                    $stableSince = Get-Date
                }

                if ((Get-Date) -ge $stableSince.AddSeconds($QuietSeconds)) {
                    return (Get-DiscordState)
                }
            } else {
                $lastFingerprint = $fingerprint
                $stableSince = Get-Date
            }
        } else {
            Write-AutoVencordLog -Phase $LogPhase -Action "wait-quiet" -Message $state.Message -Fingerprint $state.Fingerprint
            $lastFingerprint = $fingerprint
            $stableSince = $null
        }

        Start-Sleep -Seconds 2
    }

    return (Get-DiscordState)
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
            $output += Read-NativeOutputLines -Path $stdoutPath
            Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue
        }

        if (Test-Path -LiteralPath $stderrPath) {
            $output += Read-NativeOutputLines -Path $stderrPath
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

    $success = (-not $timedOut -and ($exitCode -eq 0 -or $reportedSuccess))

    return [pscustomobject]@{
        Success = $success
        ExitCode = $exitCode
        TimedOut = $timedOut
        Output = @($output)
    }
}

function Confirm-PatchRemainsPresent {
    param(
        $AppDir,
        [int]$WatchSeconds = 15,
        [int]$IntervalSeconds = 3,
        [string]$LogPhase = "RUNTIME"
    )

    $deadline = (Get-Date).AddSeconds($WatchSeconds)
    $lastPatchState = $null

    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds $IntervalSeconds
        $state = Get-DiscordState
        $patchState = Get-PatchState -AppDir $state.Latest
        $lastPatchState = $patchState

        if ($patchState.State -ne "PatchPresent") {
            Write-AutoVencordLog -Phase $LogPhase -Action "patch-lost" -Message $patchState.Reason -Fingerprint $patchState.Fingerprint
            return $patchState
        }
    }

    return $lastPatchState
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

    $discordRoot = Update-AutoVencordDiscordRoot
    $manifest = [ordered]@{
        version = $PayloadVersion
        payloadRef = $PayloadRef
        installedAt = (Get-Date).ToString("o")
        discordRoot = $discordRoot
        files = $FileHashes
    }

    $context = Get-AutoVencordContext
    Write-JsonFileAtomic -Path $context.RuntimeManifestPath -Object $manifest
}

function Get-AutoVencordStatus {
    param(
        [switch]$Fast
    )

    $context = Get-AutoVencordContext
    $discord = Get-DiscordState -SkipStabilityWait:$Fast
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

    $normalizedPath = Resolve-NormalizedPath -Path $Path
    if (-not $normalizedPath) {
        return $false
    }

    $leafName = Split-Path -Leaf $normalizedPath
    if ($leafName -like "app-*") {
        return $true
    }

    if ($normalizedPath -like "*\SquirrelTemp\*") {
        return $true
    }

    if ($normalizedPath -like "*\app-*\resources\app.asar" -or $normalizedPath -like "*\app-*\resources\_app.asar") {
        return $true
    }

    if ($normalizedPath -like "*\app-*\Discord.exe" -or $normalizedPath -like "*\app-*\Update.exe") {
        return $true
    }

    return $false
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
        param(
            [switch]$WaitForQuiet
        )

        if ($isChecking) {
            Write-AutoVencordLog -Phase "WATCHDOG" -Action "skip" -Message "Check skipped because another check is already running."
            return
        }

        $script:isChecking = $true
        $isChecking = $true

        try {
            $discordState = if ($WaitForQuiet) {
                Wait-ForDiscordFilesystemQuiet -QuietSeconds 10 -MaxWaitSeconds $context.ReadyMaxWaitSeconds -LogPhase "WATCHDOG"
            } else {
                Get-DiscordState
            }

            if ($discordState.State -ne "DiscordReady") {
                Write-AutoVencordLog -Phase "WATCHDOG" -Action "discord-state" -Message $discordState.Message -Fingerprint $discordState.Fingerprint

                if ($discordState.State -notin @("DiscordUpdating", "DiscordIncomplete")) {
                    return
                }

                $discordState = Wait-ForDiscordReady -MaxWaitSeconds $context.ReadyMaxWaitSeconds -LogPhase "WATCHDOG"
                if ($discordState.State -ne "DiscordReady") {
                    Write-AutoVencordLog -Phase "WATCHDOG" -Action "patch-postpone" -Message $discordState.Message -Fingerprint $discordState.Fingerprint
                    return
                }
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

            $readyState = Wait-ForDiscordFilesystemQuiet -QuietSeconds 10 -MaxWaitSeconds $context.ReadyMaxWaitSeconds -LogPhase "WATCHDOG"
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

            for ($patchAttempt = 1; $patchAttempt -le 2; $patchAttempt++) {
                Write-AutoVencordLog -Phase "WATCHDOG" -Action "patch-start" -Message ("Starting patch for Discord. Attempt {0}." -f $patchAttempt) -Fingerprint $recheckPatch.Fingerprint
                $restartDiscordAfterPatch = Test-DiscordClientRunning -DiscordRoot $context.DiscordRoot
                $result = Invoke-VencordCliAction -InstallerPath $context.InstallerPath -Action "install" -DiscordRoot $context.DiscordRoot -TimeoutSeconds $context.PatchTimeoutSeconds -LogPhase "WATCHDOG"
                if (-not $result.Success) {
                    Write-AutoVencordLog -Phase "WATCHDOG" -Action "patch-failed" -Message "Patch command failed." -Fingerprint $recheckPatch.Fingerprint -ExitCode $result.ExitCode
                    Resume-DiscordAfterPatchIfNeeded -WasRunning $restartDiscordAfterPatch -DiscordRoot $context.DiscordRoot -LogPhase "WATCHDOG"
                    return
                }

                Start-Sleep -Seconds 2
                $verifiedDiscordState = Get-DiscordState
                $verifiedPatchState = Get-PatchState -AppDir $verifiedDiscordState.Latest
                if ($verifiedPatchState.State -ne "PatchPresent") {
                    Write-AutoVencordLog -Phase "WATCHDOG" -Action "patch-verify-failed" -Message $verifiedPatchState.Reason -Fingerprint $verifiedPatchState.Fingerprint
                    Resume-DiscordAfterPatchIfNeeded -WasRunning $restartDiscordAfterPatch -DiscordRoot $context.DiscordRoot -LogPhase "WATCHDOG"
                    return
                }

                Resume-DiscordAfterPatchIfNeeded -WasRunning $restartDiscordAfterPatch -DiscordRoot $context.DiscordRoot -LogPhase "WATCHDOG"
                $stablePatchState = Confirm-PatchRemainsPresent -AppDir $verifiedDiscordState.Latest -WatchSeconds $context.PostPatchWatchSeconds -IntervalSeconds $context.PostPatchCheckIntervalSeconds -LogPhase "WATCHDOG"
                if ($stablePatchState.State -eq "PatchPresent") {
                    $lastSuccessfulFingerprint = $stablePatchState.Fingerprint
                    Write-AutoVencordLog -Phase "WATCHDOG" -Action "patch-verified" -Message "Patch verified successfully." -Fingerprint $stablePatchState.Fingerprint
                    return
                }

                $lastSuccessfulFingerprint = $null
                $lastAttemptFingerprint = $null
                if ($patchAttempt -ge 2) {
                    return
                }

                $readyState = Wait-ForDiscordFilesystemQuiet -QuietSeconds 10 -MaxWaitSeconds $context.ReadyMaxWaitSeconds -LogPhase "WATCHDOG"
                if ($readyState.State -ne "DiscordReady") {
                    Write-AutoVencordLog -Phase "WATCHDOG" -Action "patch-postpone" -Message $readyState.Message -Fingerprint $readyState.Fingerprint
                    return
                }

                $recheckPatch = Get-PatchState -AppDir $readyState.Latest
                if ($recheckPatch.State -eq "PatchPresent") {
                    $lastSuccessfulFingerprint = $recheckPatch.Fingerprint
                    Write-AutoVencordLog -Phase "WATCHDOG" -Action "patch-verified" -Message "Patch verified successfully." -Fingerprint $recheckPatch.Fingerprint
                    return
                }

                if ($recheckPatch.State -eq "PatchUnknown") {
                    Write-AutoVencordLog -Phase "WATCHDOG" -Action "patch-state" -Message $recheckPatch.Reason -Fingerprint $recheckPatch.Fingerprint
                    return
                }
            }
        } finally {
            $script:isChecking = $false
            $isChecking = $false
        }
    }

    try {
        while ($true) {
            $null = Update-AutoVencordDiscordRoot
            $context = Get-AutoVencordContext

            while (-not (Test-Path -LiteralPath $context.DiscordRoot)) {
                Write-AutoVencordLog -Phase "WATCHDOG" -Action "wait-root" -Message "Discord root missing, waiting for it to appear."
                Start-Sleep -Seconds 30
                $null = Update-AutoVencordDiscordRoot
                $context = Get-AutoVencordContext
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
                $context = Get-AutoVencordContext
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

                while (Test-Path -LiteralPath (Get-AutoVencordContext).DiscordRoot) {
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
                            Invoke-PatchCheck -WaitForQuiet
                        }
                    } else {
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
