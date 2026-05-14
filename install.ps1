$ErrorActionPreference = "Stop"

$installerPayloadRef = "ef66cd5"
$installerExpectedHash = "786D968F1A2EA5D84938BF07123FE52D1D37D1801E37E7D864E81288A0E27613"
$installerPinnedUrl = "https://raw.githubusercontent.com/Kevanko/AutoVencord/$installerPayloadRef/AutoVencord-Setup.ps1"
$installerUrl = "https://raw.githubusercontent.com/Kevanko/AutoVencord/main/AutoVencord-Setup.ps1"
$installerFallbackUrl = "https://github.com/Kevanko/AutoVencord/raw/main/AutoVencord-Setup.ps1"
$installerFreshMarker = "function Invoke-SchtasksSafe {"
$scriptRoot = if ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PWD.Path }
$localSetupCandidate = Join-Path $scriptRoot "AutoVencord-Setup.ps1"
$tempDir = Join-Path $env:TEMP "AutoVencord"
$setupPath = Join-Path $tempDir "AutoVencord-Setup.ps1"
$installedBaseDir = Join-Path $env:LOCALAPPDATA "AutoVencord"
$installedInstallerPath = Join-Path $installedBaseDir "AutoVencord-OneClick.bat"
$installedSetupPath = Join-Path $installedBaseDir "AutoVencord-Setup.ps1"
$installedSetupHashPath = Join-Path $installedBaseDir "AutoVencord-Setup.sha256"
$uninstallPath = Join-Path $installedBaseDir "uninstall.bat"
$watchdogScriptPath = Join-Path $installedBaseDir "watchdog.ps1"
$installedCliPath = Join-Path $installedBaseDir "VencordInstallerCli.exe"
$discordRoot = Join-Path $env:LOCALAPPDATA "Discord"
$windowTitle = "AutoVencord"
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

function Test-InstallerPayload {
    param(
        [string]$Path,
        [switch]$RequireExpectedHash
    )

    if (-not (Test-Path $Path)) {
        return $false
    }

    try {
        $content = Get-Content -LiteralPath $Path -Raw
        if (-not $content.Contains($installerFreshMarker)) {
            return $false
        }

        if ($RequireExpectedHash) {
            $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
            return $hash.ToUpperInvariant() -eq $installerExpectedHash
        }

        return $true
    } catch {
        return $false
    }
}

function Get-InstallerCandidateUrls {
    return @(
        $installerPinnedUrl,
        $installerUrl,
        $installerFallbackUrl,
        ("{0}?raw=1" -f $installerFallbackUrl)
    )
}

function Download-FreshInstallerPayload {
    param(
        [string]$OutFile,
        [switch]$AllowLocalFallback
    )

    if ($AllowLocalFallback -and (Test-InstallerPayload -Path $localSetupCandidate)) {
        Copy-Item -LiteralPath $localSetupCandidate -Destination $OutFile -Force
        return
    }

    $urls = Get-InstallerCandidateUrls
    $lastError = $null

    foreach ($url in $urls) {
        try {
            Download-File $url $OutFile

            if (Test-InstallerPayload -Path $OutFile -RequireExpectedHash) {
                return
            }
        } catch {
            $lastError = $_
        }
    }

    if ($lastError) {
        throw $lastError
    }

    throw "Downloaded installer payload is stale or invalid."
}

function Join-CodePoints {
    param(
        [int[]]$Codes
    )

    return (-join ($Codes | ForEach-Object { [char]$_ }))
}

function Get-PreferredLanguageCode {
    $candidates = @()

    if ($env:AUTOVENCORD_LANG) {
        $candidates += $env:AUTOVENCORD_LANG
    }

    try { $candidates += [System.Globalization.CultureInfo]::CurrentUICulture.Name } catch {}
    try { $candidates += [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName } catch {}
    try { $candidates += [System.Globalization.CultureInfo]::CurrentCulture.Name } catch {}
    try { $candidates += [System.Globalization.CultureInfo]::CurrentCulture.TwoLetterISOLanguageName } catch {}
    try { $candidates += (Get-UICulture).Name } catch {}
    try { $candidates += (Get-Culture).Name } catch {}
    try { $candidates += (Get-WinSystemLocale).Name } catch {}
    try { $candidates += (Get-WinUserLanguageList | ForEach-Object { $_.LanguageTag }) } catch {}

    foreach ($candidate in $candidates) {
        $value = [string]$candidate

        if ([string]::IsNullOrWhiteSpace($value)) {
            continue
        }

        if ($value -match "^(?i)ru") {
            return "ru"
        }

        if ($value -match "^(?i)en") {
            return "en"
        }
    }

    return "en"
}

function Get-UiText {
    $language = Get-PreferredLanguageCode

    if ($language -eq "ru") {
        return @{
            Language = "ru"
            BannerTitle = "AutoVencord"
            BannerHint = Join-CodePoints @(1057,1090,1088,1077,1083,1082,1080,32,1074,1074,1077,1088,1093,47,1074,1085,1080,1079,32,45,32,1074,1099,1073,1086,1088,44,32,69,110,116,101,114,32,45,32,1079,1072,1087,1091,1089,1082,44,32,69,115,99,32,45,32,1074,1099,1093,1086,1076)
            SectionTitle = Join-CodePoints @(1059,1089,1090,1072,1085,1086,1074,1082,1072,32,1080,32,1086,1073,1089,1083,1091,1078,1080,1074,1072,1085,1080,1077)
            Installed = Join-CodePoints @(1059,1089,1090,1072,1085,1086,1074,1083,1077,1085,1086)
            Yes = Join-CodePoints @(1044,1072)
            No = Join-CodePoints @(1053,1077,1090)
            Watchdog = "Watchdog"
            Discord = "Discord"
            Active = Join-CodePoints @(1040,1082,1090,1080,1074,1077,1085)
            Inactive = Join-CodePoints @(1053,1077,1072,1082,1090,1080,1074,1077,1085)
            NotInstalled = Join-CodePoints @(1053,1077,32,1091,1089,1090,1072,1085,1086,1074,1083,1077,1085)
            Unknown = Join-CodePoints @(1053,1077,1080,1079,1074,1077,1089,1090,1085,1086)
            DiscordMissing = Join-CodePoints @(1085,1077,32,1085,1072,1081,1076,1077,1085)
            DiscordIncomplete = Join-CodePoints @(1085,1077,1087,1086,1083,1085,1072,1103,32,1091,1089,1090,1072,1085,1086,1074,1082,1072,32,47,32,1086,1073,1085,1086,1074,1083,1103,1077,1090,1089,1103)
            DiscordMissingInstalled = Join-CodePoints @(68,105,115,99,111,114,100,32,1085,1077,32,1085,1072,1081,1076,1077,1085,46,32,65,117,116,111,86,101,110,99,111,114,100,32,1073,1086,1083,1100,1096,1077,32,1085,1077,32,1089,1084,1086,1078,1077,1090,32,1088,1072,1073,1086,1090,1072,1090,1100,44,32,1087,1086,1082,1072,32,68,105,115,99,111,114,100,32,1085,1077,32,1091,1089,1090,1072,1085,1086,1074,1083,1077,1085,46)
            DiscordIncompleteMessage = Join-CodePoints @(68,105,115,99,111,114,100,32,1091,1089,1090,1072,1085,1086,1074,1083,1077,1085,32,1085,1077,1087,1086,1083,1085,1086,32,1080,1083,1080,32,1086,1073,1085,1086,1074,1083,1103,1077,1090,1089,1103,46,32,1047,1072,1087,1091,1089,1090,1080,1090,1077,32,68,105,115,99,111,114,100,32,1086,1076,1080,1085,32,1088,1072,1079,32,1080,32,1087,1086,1074,1090,1086,1088,1080,1090,1077,46)
            DiscordMissingInstall = Join-CodePoints @(1059,1089,1090,1072,1085,1086,1074,1080,1090,1077,32,68,105,115,99,111,114,100,32,1087,1077,1088,1077,1076,32,1091,1089,1090,1072,1085,1086,1074,1082,1086,1081,32,65,117,116,111,86,101,110,99,111,114,100,46)
            Install = Join-CodePoints @(1059,1089,1090,1072,1085,1086,1074,1080,1090,1100)
            Update = Join-CodePoints @(1054,1073,1085,1086,1074,1080,1090,1100)
            Uninstall = Join-CodePoints @(1059,1076,1072,1083,1080,1090,1100)
            OpenFolder = Join-CodePoints @(1054,1090,1082,1088,1099,1090,1100,32,1087,1072,1087,1082,1091)
            Exit = Join-CodePoints @(1042,1099,1093,1086,1076)
            Downloading = Join-CodePoints @(1057,1082,1072,1095,1080,1074,1072,1102,32,1072,1082,1090,1091,1072,1083,1100,1085,1099,1081,32,1091,1089,1090,1072,1085,1086,1074,1097,1080,1082,32,65,117,116,111,86,101,110,99,111,114,100,46,46,46)
            Updating = Join-CodePoints @(1054,1073,1085,1086,1074,1083,1103,1102,32,65,117,116,111,86,101,110,99,111,114,100,46,46,46)
            RunningUninstall = Join-CodePoints @(1047,1072,1087,1091,1089,1082,1072,1102,32,1091,1076,1072,1083,1077,1085,1080,1077,32,65,117,116,111,86,101,110,99,111,114,100,46,46,46)
            MissingUninstall = Join-CodePoints @(65,117,116,111,86,101,110,99,111,114,100,32,1085,1077,32,1091,1089,1090,1072,1085,1086,1074,1083,1077,1085,46)
            AlreadyLatest = Join-CodePoints @(1059,32,1074,1072,1089,32,1072,1082,1090,1091,1072,1083,1100,1085,1072,1103,32,1074,1077,1088,1089,1080,1103,46)
            ConfirmInstallTitle = Join-CodePoints @(1042,1099,1073,1088,1072,1085,1072,32,1091,1089,1090,1072,1085,1086,1074,1082,1072,46)
            ConfirmInstallEnter = Join-CodePoints @(1053,1072,1078,1084,1080,32,69,110,116,101,114,32,1077,1097,1077,32,1088,1072,1079,32,1076,1083,1103,32,1087,1086,1076,1090,1074,1077,1088,1078,1076,1077,1085,1080,1103,46)
            ConfirmInstallEsc = Join-CodePoints @(1053,1072,1078,1084,1080,32,69,115,99,44,32,1095,1090,1086,1073,1099,32,1074,1077,1088,1085,1091,1090,1100,1089,1103,32,1085,1072,1079,1072,1076,46)
            InstallDone = Join-CodePoints @(1059,1089,1090,1072,1085,1086,1074,1083,1077,1085,1086,32,1091,1089,1087,1077,1096,1085,1086,46)
            UpdateDone = Join-CodePoints @(1054,1073,1085,1086,1074,1083,1077,1085,1086,32,1091,1089,1087,1077,1096,1085,1086,46)
            UninstallDone = Join-CodePoints @(1059,1076,1072,1083,1077,1085,1086,32,1091,1089,1087,1077,1096,1085,1086,46)
            ResultHint = Join-CodePoints @(1053,1072,1078,1084,1080,1090,1077,32,69,110,116,101,114,44,32,1095,1090,1086,1073,1099,32,1074,1077,1088,1085,1091,1090,1100,1089,1103,32,1074,32,1084,1077,1085,1102,46,32,69,115,99,32,45,32,1074,1099,1081,1090,1080,46)
            UpdateAvailableSuffix = " *"
            UpdateStatusLabel = Join-CodePoints @(1054,1073,1085,1086,1074,1083,1077,1085,1080,1077)
            UpdateAvailable = Join-CodePoints @(1044,1086,1089,1090,1091,1087,1085,1086)
            UpdateCurrent = Join-CodePoints @(1040,1082,1090,1091,1072,1083,1100,1085,1086)
            UpdateUnavailable = Join-CodePoints @(1053,1077,1076,1086,1089,1090,1091,1087,1085,1086)
            UpdateHintAvailable = Join-CodePoints @(1084,1086,1078,1085,1086,32,1086,1073,1085,1086,1074,1080,1090,1100)
            UpdateHintCurrent = Join-CodePoints @(1072,1082,1090,1091,1072,1083,1100,1085,1086)
            UpdateHintUnavailable = Join-CodePoints @(1085,1077,32,1091,1089,1090,1072,1085,1086,1074,1083,1077,1085)
        }
    }

    return @{
        Language = "en"
        BannerTitle = "AutoVencord"
        BannerHint = "Use Up/Down arrows to move, Enter to run"
        SectionTitle = "Setup and Maintenance"
        Installed = "Installed"
        Yes = "Yes"
        No = "No"
        Watchdog = "Watchdog"
        Discord = "Discord"
        Active = "Active"
        Inactive = "Inactive"
        NotInstalled = "Not installed"
        Unknown = "Unknown"
        DiscordMissing = "not found"
        DiscordIncomplete = "incomplete / updating"
        DiscordMissingInstalled = "Discord is missing. AutoVencord cannot work until Discord is installed."
        DiscordIncompleteMessage = "Discord looks incomplete or is updating. Start Discord once, then try again."
        DiscordMissingInstall = "Install Discord before installing AutoVencord."
        Install = "Install"
        Update = "Update"
        Uninstall = "Uninstall"
        OpenFolder = "Open Folder"
        Exit = "Exit"
        Downloading = "Downloading latest AutoVencord installer..."
        Updating = "Updating AutoVencord..."
        RunningUninstall = "Running AutoVencord uninstaller..."
        MissingUninstall = "AutoVencord is not installed."
        AlreadyLatest = "You already have the latest version."
        ConfirmInstallTitle = "Install selected."
        ConfirmInstallEnter = "Press Enter again to confirm installation."
        ConfirmInstallEsc = "Press Esc to go back."
        InstallDone = "Installed successfully."
        UpdateDone = "Updated successfully."
        UninstallDone = "Uninstalled successfully."
        ResultHint = "Press Enter to return to menu. Esc exits."
        UpdateAvailableSuffix = " *"
        UpdateStatusLabel = "Update"
        UpdateAvailable = "Available"
        UpdateCurrent = "Current"
        UpdateUnavailable = "Unavailable"
        UpdateHintAvailable = "update available"
        UpdateHintCurrent = "current"
        UpdateHintUnavailable = "not installed"
    }
}

function Get-WatchdogState {
    if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
        try {
            $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
            return [string]$task.State
        } catch {
            return "NotInstalled"
        }
    }

    try {
        $output = & schtasks.exe /Query /TN $taskName /FO LIST 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $output) {
            return "NotInstalled"
        }

        $statusLine = $output | Where-Object { $_ -like "Status:*" } | Select-Object -First 1
        if ($statusLine) {
            return ($statusLine -replace "^Status:\s*", "").Trim()
        }
    } catch {}

    return "Unknown"
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
    if (-not (Test-Path $discordRoot)) {
        return $null
    }

    $latest = $null
    $latestVersion = [version]"0.0.0.0"
    $latestWriteTime = [datetime]::MinValue

    $dirs = Get-ChildItem $discordRoot -ErrorAction SilentlyContinue |
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

function Test-DiscordInstallReady {
    param(
        $AppDir
    )

    if (-not $AppDir) {
        return $false
    }

    $resources = Join-Path $AppDir.FullName "resources"
    $appAsar = Join-Path $resources "app.asar"
    $buildInfo = Join-Path $resources "build_info.json"

    return ((Test-Path $resources) -and (Test-Path $appAsar) -and (Test-Path $buildInfo))
}

function Get-DiscordPreflight {
    if (-not (Test-Path $discordRoot)) {
        return [pscustomobject]@{
            State = "Missing"
            Latest = $null
        }
    }

    $latest = Get-LatestDiscordInstall

    if (-not $latest) {
        return [pscustomobject]@{
            State = "Incomplete"
            Latest = $null
        }
    }

    if (-not (Test-DiscordInstallReady -AppDir $latest)) {
        return [pscustomobject]@{
            State = "Incomplete"
            Latest = $latest
        }
    }

    return [pscustomobject]@{
        State = "Ready"
        Latest = $latest
    }
}

function Get-StatusText {
    param(
        [hashtable]$Ui
    )

    $hasCoreFiles = (Test-Path $installedSetupPath) -or (Test-Path $installedInstallerPath) -or (Test-Path $watchdogScriptPath) -or (Test-Path $installedCliPath)
    $isInstalled = (Test-Path $uninstallPath) -and $hasCoreFiles
    $watchdogState = Get-WatchdogState
    $discord = Get-DiscordPreflight
    $installedValue = if ($isInstalled) { $Ui.Yes } else { $Ui.No }

    if ($watchdogState -match "Ready|Running") {
        $watchdogValue = "{0} ({1})" -f $Ui.Active, $watchdogState
    } elseif ($watchdogState -eq "NotInstalled") {
        $watchdogValue = $Ui.NotInstalled
    } elseif ($watchdogState -eq "Unknown") {
        $watchdogValue = $Ui.Unknown
    } else {
        $watchdogValue = "{0} ({1})" -f $Ui.Inactive, $watchdogState
    }

    $discordValue = $null
    $discordMessage = $null

    if ($discord.State -eq "Missing") {
        $discordValue = $Ui.DiscordMissing
        $discordMessage = if ($isInstalled) { $Ui.DiscordMissingInstalled } else { $Ui.DiscordMissingInstall }
    } elseif ($discord.State -eq "Incomplete") {
        $discordValue = $Ui.DiscordIncomplete
        $discordMessage = $Ui.DiscordIncompleteMessage
    }

    return [pscustomobject]@{
        InstalledLabel = $Ui.Installed
        InstalledValue = $installedValue
        InstalledOk = $isInstalled
        InstallFolderExists = (Test-Path $installedBaseDir)
        WatchdogLabel = $Ui.Watchdog
        WatchdogValue = $watchdogValue
        WatchdogOk = ($watchdogState -match "Ready|Running")
        RawWatchdogState = $watchdogState
        DiscordLabel = $Ui.Discord
        DiscordState = $discord.State
        DiscordValue = $discordValue
        DiscordMessage = $discordMessage
    }
}

function Write-PaddedLine {
    param(
        [string]$Text = "",
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::Gray,
        [int]$Width = 80
    )

    $safeWidth = [Math]::Max(20, $Width)
    $trimmed = if ($Text.Length -gt $safeWidth) { $Text.Substring(0, $safeWidth) } else { $Text }
    $padded = $trimmed.PadRight($safeWidth)
    Write-Host $padded -ForegroundColor $ForegroundColor
}

function Write-SelectedLine {
    param(
        [string]$Text = "",
        [int]$Width = 80,
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::Black,
        [ConsoleColor]$BackgroundColor = [ConsoleColor]::Cyan
    )

    $safeWidth = [Math]::Max(20, $Width)
    $trimmed = if ($Text.Length -gt $safeWidth) { $Text.Substring(0, $safeWidth) } else { $Text }
    $padded = $trimmed.PadRight($safeWidth)
    Write-Host $padded -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor
}

function Test-SameFileHash {
    param(
        [string]$LeftPath,
        [string]$RightPath
    )

    if (-not (Test-Path $LeftPath) -or -not (Test-Path $RightPath)) {
        return $false
    }

    try {
        $leftHash = (Get-FileHash -LiteralPath $LeftPath -Algorithm SHA256).Hash
        $rightHash = (Get-FileHash -LiteralPath $RightPath -Algorithm SHA256).Hash
        return $leftHash -eq $rightHash
    } catch {
        return $false
    }
}

function Get-FileSha256 {
    param(
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return $null
    }

    try {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    } catch {
        return $null
    }
}

function Get-InstalledSetupHash {
    $setupHash = Get-FileSha256 -Path $installedSetupPath
    if ($setupHash) {
        return $setupHash.ToUpperInvariant()
    }

    if (Test-Path $installedSetupHashPath) {
        try {
            $hash = (Get-Content -LiteralPath $installedSetupHashPath -Raw).Trim()

            if ($hash -match "^[A-Fa-f0-9]{64}$") {
                return $hash.ToUpperInvariant()
            }
        } catch {}
    }

    $batchHash = Get-FileSha256 -Path $installedInstallerPath
    if ($batchHash) {
        return $batchHash.ToUpperInvariant()
    }

    return $null
}

function Test-InstalledSetupMatches {
    param(
        [string]$CandidatePath
    )

    $candidateHash = Get-FileSha256 -Path $CandidatePath
    $installedHash = Get-InstalledSetupHash

    if (-not $candidateHash -or -not $installedHash) {
        return $false
    }

    return $candidateHash.ToUpperInvariant() -eq $installedHash.ToUpperInvariant()
}

function Get-UpdateAvailability {
    param(
        [pscustomobject]$Status,
        [hashtable]$Ui
    )

    if (-not $Status.InstalledOk) {
        return $false
    }

    if ($Status.DiscordState -ne "Ready") {
        return $false
    }

    try {
        $updateCheckPath = Join-Path $tempDir "AutoVencord-update-check.ps1"
        New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
        Download-FreshInstallerPayload -OutFile $updateCheckPath

        return (-not (Test-InstalledSetupMatches -CandidatePath $updateCheckPath))
    } catch {
        return $false
    }
}

function Get-MenuEnabledStates {
    param(
        [pscustomobject]$Status
    )

    if ($Status.DiscordState -ne "Ready") {
        if ($Status.InstalledOk) {
            return @(
                $false,
                $false,
                $false,
                $true,
                $true
            )
        }

        return @(
            $false,
            $false,
            $Status.InstallFolderExists,
            $false,
            $true
        )
    }

    return @(
        (-not $Status.InstalledOk),
        $Status.InstalledOk,
        $true,
        $Status.InstalledOk,
        $true
    )
}

function Resolve-MenuIndex {
    param(
        [int]$InitialIndex,
        [bool[]]$EnabledStates
    )

    if (-not $EnabledStates -or $EnabledStates.Length -eq 0) {
        return 0
    }

    $index = [Math]::Min([Math]::Max($InitialIndex, 0), $EnabledStates.Length - 1)

    if ($EnabledStates[$index]) {
        return $index
    }

    for ($offset = 1; $offset -lt $EnabledStates.Length; $offset++) {
        $downIndex = $index + $offset
        if ($downIndex -lt $EnabledStates.Length -and $EnabledStates[$downIndex]) {
            return $downIndex
        }

        $upIndex = $index - $offset
        if ($upIndex -ge 0 -and $EnabledStates[$upIndex]) {
            return $upIndex
        }
    }

    return 0
}

function Set-UpdateMenuStatus {
    param(
        [pscustomobject]$Status,
        [hashtable]$Ui,
        [bool]$UpdateAvailable
    )

    if ($Status.DiscordState -ne "Ready") {
        $value = $Ui.UpdateUnavailable
        $hint = $Status.DiscordValue
        $state = "Unavailable"
    } elseif (-not $Status.InstalledOk) {
        $value = $Ui.UpdateUnavailable
        $hint = $Ui.UpdateHintUnavailable
        $state = "Unavailable"
    } elseif ($UpdateAvailable) {
        $value = $Ui.UpdateAvailable
        $hint = $Ui.UpdateHintAvailable
        $state = "Available"
    } else {
        $value = $Ui.UpdateCurrent
        $hint = $Ui.UpdateHintCurrent
        $state = "Current"
    }

    $Status | Add-Member -MemberType NoteProperty -Name UpdateLabel -Value $Ui.UpdateStatusLabel -Force
    $Status | Add-Member -MemberType NoteProperty -Name UpdateValue -Value $value -Force
    $Status | Add-Member -MemberType NoteProperty -Name UpdateHint -Value $hint -Force
    $Status | Add-Member -MemberType NoteProperty -Name UpdateState -Value $state -Force
    $Status | Add-Member -MemberType NoteProperty -Name UpdateAvailable -Value $UpdateAvailable -Force
}

function Get-UpdateColor {
    param(
        [pscustomobject]$Status
    )

    if ($Status.UpdateState -eq "Available") {
        return [ConsoleColor]::Yellow
    }

    if ($Status.UpdateState -eq "Current") {
        return [ConsoleColor]::Green
    }

    return [ConsoleColor]::DarkGray
}

function Get-MenuItemColor {
    param(
        [int]$Index,
        [pscustomobject]$Status
    )

    if ($Index -eq 0) {
        return [ConsoleColor]::Green
    }

    if ($Index -eq 1) {
        return Get-UpdateColor -Status $Status
    }

    if ($Index -eq 3) {
        return [ConsoleColor]::Red
    }

    if ($Index -eq 4) {
        return [ConsoleColor]::White
    }

    return [ConsoleColor]::Gray
}

function Get-MenuSelectionBackground {
    param(
        [int]$Index,
        [pscustomobject]$Status
    )

    if ($Index -eq 0) {
        return [ConsoleColor]::Green
    }

    if ($Index -eq 1) {
        return Get-UpdateColor -Status $Status
    }

    if ($Index -eq 3) {
        return [ConsoleColor]::Red
    }

    if ($Index -eq 4) {
        return [ConsoleColor]::White
    }

    return [ConsoleColor]::Cyan
}

function Clear-PendingConsoleInput {
    try {
        while ([Console]::KeyAvailable) {
            [void][Console]::ReadKey($true)
        }
    } catch {}
}

function Render-Menu {
    param(
        [hashtable]$Ui,
        [pscustomobject]$Status,
        [string[]]$Options,
        [bool[]]$EnabledStates,
        [int]$SelectedIndex,
        [bool]$FirstRender
    )

    $rawUi = $Host.UI.RawUI
    $width = [Math]::Max(62, $rawUi.WindowSize.Width - 1)

    if ($FirstRender) {
        Clear-Host
    }

    $rawUi.CursorPosition = New-Object System.Management.Automation.Host.Coordinates 0, 0

    Write-PaddedLine -Text ("=" * $width) -ForegroundColor DarkCyan -Width $width
    Write-PaddedLine -Text ("{0}" -f $Ui.BannerTitle).PadLeft(([Math]::Floor(($width + $Ui.BannerTitle.Length) / 2))) -ForegroundColor Cyan -Width $width
    Write-PaddedLine -Text ("=" * $width) -ForegroundColor DarkCyan -Width $width
    Write-PaddedLine -Text "" -Width $width
    Write-PaddedLine -Text $Ui.BannerHint -ForegroundColor DarkGray -Width $width
    Write-PaddedLine -Text "" -Width $width
    Write-PaddedLine -Text $Ui.SectionTitle -ForegroundColor Green -Width $width
    Write-PaddedLine -Text "" -Width $width

    $installedColor = if ($Status.InstalledOk) { [ConsoleColor]::Green } else { [ConsoleColor]::Yellow }
    $watchdogColor = if ($Status.WatchdogOk) { [ConsoleColor]::Green } elseif ($Status.RawWatchdogState -eq "NotInstalled") { [ConsoleColor]::Yellow } else { [ConsoleColor]::DarkYellow }

    Write-PaddedLine -Text ("{0}: {1}" -f $Status.InstalledLabel, $Status.InstalledValue) -ForegroundColor $installedColor -Width $width
    Write-PaddedLine -Text ("{0}: {1}" -f $Status.WatchdogLabel, $Status.WatchdogValue) -ForegroundColor $watchdogColor -Width $width

    if ($Status.DiscordState -ne "Ready") {
        $discordColor = if ($Status.DiscordState -eq "Missing") { [ConsoleColor]::Red } else { [ConsoleColor]::Yellow }
        Write-PaddedLine -Text ("{0}: {1}" -f $Status.DiscordLabel, $Status.DiscordValue) -ForegroundColor $discordColor -Width $width
        if ($Status.DiscordMessage) {
            Write-PaddedLine -Text $Status.DiscordMessage -ForegroundColor $discordColor -Width $width
        }
    }

    if ($Status.UpdateLabel) {
        Write-PaddedLine -Text ("{0}: {1}" -f $Status.UpdateLabel, $Status.UpdateValue) -ForegroundColor (Get-UpdateColor -Status $Status) -Width $width
    }

    Write-PaddedLine -Text "" -Width $width

    for ($i = 0; $i -lt $Options.Length; $i++) {
        $label = $Options[$i]
        $enabled = $EnabledStates[$i]
        $marker = if ($i -eq $SelectedIndex) { " >>" } else { "   " }
        $rightHint = if ($i -eq 1 -and $Status.UpdateHint) { $Status.UpdateHint } else { "" }
        $contentWidth = [Math]::Max(20, $width - $marker.Length)
        $left = ("  {0}" -f $label)
        $right = if ($rightHint) { " " + $rightHint } else { "" }

        if ($right -and ($contentWidth - $right.Length) -ge 18) {
            $leftWidth = $contentWidth - $right.Length
            if ($left.Length -gt $leftWidth) {
                $left = $left.Substring(0, $leftWidth)
            }

            $line = $left.PadRight($leftWidth) + $right + $marker
        } else {
            if ($left.Length -gt $contentWidth) {
                $left = $left.Substring(0, $contentWidth)
            }

            $line = $left.PadRight($contentWidth) + $marker
        }

        $lineColor = Get-MenuItemColor -Index $i -Status $Status
        $selectedBackground = Get-MenuSelectionBackground -Index $i -Status $Status
        $selectedForeground = if ($selectedBackground -eq [ConsoleColor]::Red) { [ConsoleColor]::White } else { [ConsoleColor]::Black }

        if (-not $enabled) {
            Write-PaddedLine -Text $line -ForegroundColor DarkGray -Width $width
        } elseif ($i -eq $SelectedIndex) {
            Write-SelectedLine -Text $line -Width $width -ForegroundColor $selectedForeground -BackgroundColor $selectedBackground
        } else {
            Write-PaddedLine -Text $line -ForegroundColor $lineColor -Width $width
        }
    }

    Write-PaddedLine -Text "" -Width $width
    Write-PaddedLine -Text "" -Width $width
}

function Confirm-InstallSelection {
    param(
        [hashtable]$Ui
    )

    $rawUi = $Host.UI.RawUI
    $width = [Math]::Max(62, $rawUi.WindowSize.Width - 1)

    Clear-Host
    $rawUi.CursorPosition = New-Object System.Management.Automation.Host.Coordinates 0, 0

    Write-PaddedLine -Text ("=" * $width) -ForegroundColor DarkCyan -Width $width
    Write-PaddedLine -Text ("{0}" -f $Ui.BannerTitle).PadLeft(([Math]::Floor(($width + $Ui.BannerTitle.Length) / 2))) -ForegroundColor Cyan -Width $width
    Write-PaddedLine -Text ("=" * $width) -ForegroundColor DarkCyan -Width $width
    Write-PaddedLine -Text "" -Width $width
    Write-PaddedLine -Text ("  " + $Ui.ConfirmInstallTitle) -ForegroundColor Yellow -Width $width
    Write-PaddedLine -Text ("  " + $Ui.ConfirmInstallEnter) -ForegroundColor Gray -Width $width
    Write-PaddedLine -Text ("  " + $Ui.ConfirmInstallEsc) -ForegroundColor DarkGray -Width $width
    Write-PaddedLine -Text "" -Width $width

    while ($true) {
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

        if ($key.VirtualKeyCode -eq 13) {
            return $true
        }

        if ($key.VirtualKeyCode -eq 27) {
            return $false
        }
    }
}

function Show-ActionResult {
    param(
        [hashtable]$Ui,
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::Green
    )

    $rawUi = $Host.UI.RawUI
    $width = [Math]::Max(62, $rawUi.WindowSize.Width - 1)

    Clear-Host
    $rawUi.CursorPosition = New-Object System.Management.Automation.Host.Coordinates 0, 0

    Write-PaddedLine -Text ("=" * $width) -ForegroundColor DarkCyan -Width $width
    Write-PaddedLine -Text ("{0}" -f $Ui.BannerTitle).PadLeft(([Math]::Floor(($width + $Ui.BannerTitle.Length) / 2))) -ForegroundColor Cyan -Width $width
    Write-PaddedLine -Text ("=" * $width) -ForegroundColor DarkCyan -Width $width
    Write-PaddedLine -Text "" -Width $width
    Write-PaddedLine -Text ("  " + $Message) -ForegroundColor $Color -Width $width
    Write-PaddedLine -Text ("  " + $Ui.ResultHint) -ForegroundColor DarkGray -Width $width
    Write-PaddedLine -Text "" -Width $width

    Start-Sleep -Milliseconds 150
    Clear-PendingConsoleInput

    while ($true) {
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

        if ($key.VirtualKeyCode -eq 13) {
            return $true
        }

        if ($key.VirtualKeyCode -eq 27) {
            return $false
        }
    }
}

function Download-LatestInstaller {
    param(
        [hashtable]$Ui,
        [switch]$AllowLocalFallback
    )

    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
    Write-Host $Ui.Downloading -ForegroundColor Cyan
    Download-FreshInstallerPayload -OutFile $setupPath -AllowLocalFallback:$AllowLocalFallback
    return $setupPath
}

function Assert-DiscordReady {
    param(
        [hashtable]$Ui
    )

    $discord = Get-DiscordPreflight

    if ($discord.State -eq "Ready") {
        return
    }

    if ($discord.State -eq "Missing") {
        throw $Ui.DiscordMissingInstall
    }

    throw $Ui.DiscordIncompleteMessage
}

function Invoke-SetupScript {
    param(
        [string]$SetupScriptPath,
        [switch]$PatchNow
    )

    $oldSkipSelfUpdate = $env:AUTOVENCORD_SKIP_SELF_UPDATE
    $oldNoPause = $env:AUTOVENCORD_NO_PAUSE

    try {
        $env:AUTOVENCORD_SKIP_SELF_UPDATE = "1"
        $env:AUTOVENCORD_NO_PAUSE = "1"
        $setupArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $SetupScriptPath, "-SourceSetupPath", $SetupScriptPath)

        if ($PatchNow) {
            $setupArgs += "-PatchNow"
        }

        & powershell.exe @setupArgs
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0) {
            throw "AutoVencord installer failed with exit code $exitCode"
        }
    } finally {
        $env:AUTOVENCORD_SKIP_SELF_UPDATE = $oldSkipSelfUpdate
        $env:AUTOVENCORD_NO_PAUSE = $oldNoPause
    }
}

function Show-Menu {
    param(
        [hashtable]$Ui,
        [string[]]$Options,
        [int]$InitialIndex = 0
    )

    $firstRender = $true
    $status = Get-StatusText -Ui $Ui
    $updateAvailable = Get-UpdateAvailability -Status $status -Ui $Ui
    Set-UpdateMenuStatus -Status $status -Ui $Ui -UpdateAvailable $updateAvailable
    $menuOptions = $Options

    $enabledStates = Get-MenuEnabledStates -Status $status
    $index = Resolve-MenuIndex -InitialIndex $InitialIndex -EnabledStates $enabledStates

    try {
        $Host.UI.RawUI.WindowTitle = $windowTitle
    } catch {}

    Start-Sleep -Milliseconds 150
    Clear-PendingConsoleInput

    while ($true) {
        Render-Menu -Ui $Ui -Status $status -Options $menuOptions -EnabledStates $enabledStates -SelectedIndex $index -FirstRender $firstRender
        $firstRender = $false

        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

        if ($key.VirtualKeyCode -eq 38) {
            for ($i = $index - 1; $i -ge 0; $i--) {
                if ($enabledStates[$i]) {
                    $index = $i
                    break
                }
            }

            continue
        }

        if ($key.VirtualKeyCode -eq 40) {
            for ($i = $index + 1; $i -lt $Options.Length; $i++) {
                if ($enabledStates[$i]) {
                    $index = $i
                    break
                }
            }

            continue
        }

        if ($key.VirtualKeyCode -eq 13) {
            if ($enabledStates[$index]) {
                return $index
            }
        }

        if ($key.VirtualKeyCode -eq 27) {
            return -1
        }
    }
}

function Invoke-Install {
    param(
        [hashtable]$Ui
    )

    Assert-DiscordReady -Ui $Ui
    $downloadedInstallerPath = Download-LatestInstaller -Ui $Ui -AllowLocalFallback
    Invoke-SetupScript -SetupScriptPath $downloadedInstallerPath -PatchNow
}

function Invoke-Uninstall {
    param(
        [hashtable]$Ui
    )

    if (-not (Test-Path $uninstallPath)) {
        Write-Host $Ui.MissingUninstall -ForegroundColor Yellow
        return
    }

    Write-Host $Ui.RunningUninstall -ForegroundColor Yellow
    $oldNoPause = $env:AUTOVENCORD_NO_PAUSE

    try {
        $env:AUTOVENCORD_NO_PAUSE = "1"
        & $uninstallPath
        $exitCode = $LASTEXITCODE
    } finally {
        $env:AUTOVENCORD_NO_PAUSE = $oldNoPause
    }

    if ($exitCode -ne 0) {
        throw "AutoVencord uninstaller failed with exit code $exitCode"
    }
}

function Invoke-Update {
    param(
        [hashtable]$Ui
    )

    Assert-DiscordReady -Ui $Ui
    Write-Host $Ui.Updating -ForegroundColor Cyan
    $downloadedInstallerPath = Download-LatestInstaller -Ui $Ui

    if (Test-InstalledSetupMatches -CandidatePath $downloadedInstallerPath) {
        Write-Host $Ui.AlreadyLatest -ForegroundColor Green
        return $false
    }

    Invoke-SetupScript -SetupScriptPath $downloadedInstallerPath -PatchNow
    return $true
}

function Open-InstallFolder {
    New-Item -ItemType Directory -Force -Path $installedBaseDir | Out-Null
    Start-Process explorer.exe $installedBaseDir
}

$ui = Get-UiText
$autoAction = $env:AUTOVENCORD_MENU_ACTION
$options = @($ui.Install, $ui.Update, $ui.OpenFolder, $ui.Uninstall, $ui.Exit)
$selectedIndex = 0

while ($true) {
    $selection = $null

    if ($autoAction) {
        switch ($autoAction.ToLowerInvariant()) {
            "install" { $selection = 0 }
            "update" { $selection = 1 }
            "open" { $selection = 2 }
            "uninstall" { $selection = 3 }
            "exit" { $selection = 4 }
        }
    }

    if ($null -eq $selection) {
        $selection = Show-Menu -Ui $ui -Options $options -InitialIndex $selectedIndex
        $selectedIndex = $selection
    }

    if ($selection -eq -1 -or $selection -eq 4) {
        break
    }

    if (-not $autoAction -and $selection -eq 0) {
        if (-not (Confirm-InstallSelection -Ui $ui)) {
            continue
        }
    }

    if ($selection -eq 2) {
        Open-InstallFolder

        if ($autoAction) {
            break
        }

        continue
    }

    Clear-Host

    if ($selection -eq 0) {
        Invoke-Install -Ui $ui
        if (-not $autoAction) {
            if (Show-ActionResult -Ui $ui -Message $ui.InstallDone -Color Green) {
                continue
            }
        }
    } elseif ($selection -eq 1) {
        $updateApplied = Invoke-Update -Ui $ui

        if (-not $autoAction) {
            $updateMessage = if ($updateApplied) { $ui.UpdateDone } else { $ui.AlreadyLatest }
            if (Show-ActionResult -Ui $ui -Message $updateMessage -Color Green) {
                continue
            }
        }
    } elseif ($selection -eq 3) {
        Invoke-Uninstall -Ui $ui
        if (-not $autoAction) {
            if (Show-ActionResult -Ui $ui -Message $ui.UninstallDone -Color Green) {
                continue
            }
        }
    }

    break
}
