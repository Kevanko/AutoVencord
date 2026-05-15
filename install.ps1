$ErrorActionPreference = "Stop"

$AUTOVENCORD_PAYLOAD_VERSION = "2026.05.15.1"
$installerPayloadRef = "main"
$installerPayloadMarker = "AUTOVENCORD_PAYLOAD_VERSION"
$windowTitle = "AutoVencord"
$scriptRoot = if ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PWD.Path }
$tempDir = Join-Path $env:TEMP "AutoVencord"
$setupPath = Join-Path $tempDir "AutoVencord-Setup.ps1"
$payloadManifestTempPath = Join-Path $tempDir "AutoVencord-Payload.json"
$coreTempPath = Join-Path $tempDir "AutoVencord.Core.ps1"
$installedBaseDir = Join-Path $env:LOCALAPPDATA "AutoVencord"

function Enable-Tls12IfAvailable {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]3072
    } catch {}
}

function Invoke-BootstrapDownload {
    param(
        [string[]]$Urls,
        [string]$DestinationPath,
        [scriptblock]$ValidationScript
    )

    Enable-Tls12IfAvailable
    $directory = Split-Path -Parent $DestinationPath
    if ($directory) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }

    $lastError = $null
    foreach ($url in $Urls) {
        $tempPath = "{0}.{1}.tmp" -f $DestinationPath, ([guid]::NewGuid().ToString("N"))
        try {
            if (Get-Command Invoke-WebRequest -ErrorAction SilentlyContinue) {
                Invoke-WebRequest -UseBasicParsing $url -OutFile $tempPath
            } else {
                $client = New-Object System.Net.WebClient
                $client.DownloadFile($url, $tempPath)
            }

            if ($ValidationScript -and -not (& $ValidationScript $tempPath)) {
                throw "Downloaded file did not pass validation."
            }

            Move-Item -LiteralPath $tempPath -Destination $DestinationPath -Force
            return $true
        } catch {
            $lastError = $_
        } finally {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }

    if ($lastError) {
        throw $lastError
    }

    throw "Unable to download required bootstrap file."
}

function Get-PayloadCandidateUrls {
    param(
        [string]$FileName
    )

    return @(
        "https://raw.githubusercontent.com/Kevanko/AutoVencord/$installerPayloadRef/${FileName}",
        "https://raw.githubusercontent.com/Kevanko/AutoVencord/main/${FileName}",
        "https://github.com/Kevanko/AutoVencord/raw/main/${FileName}",
        "https://github.com/Kevanko/AutoVencord/raw/main/${FileName}?raw=1"
    )
}

function Test-CorePayload {
    param(
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    try {
        $content = Get-Content -LiteralPath $Path -Raw
        return ($content.Contains("Get-AutoVencordPayloadVersion") -and $content.Contains($AUTOVENCORD_PAYLOAD_VERSION))
    } catch {
        return $false
    }
}

function Initialize-CoreModule {
    $localCorePath = Join-Path $scriptRoot "AutoVencord.Core.ps1"
    if (Test-Path -LiteralPath $localCorePath) {
        return $localCorePath
    }

    $null = Invoke-BootstrapDownload -Urls (Get-PayloadCandidateUrls -FileName "AutoVencord.Core.ps1") -DestinationPath $coreTempPath -ValidationScript ${function:Test-CorePayload}
    return $coreTempPath
}

$resolvedCorePath = Initialize-CoreModule
. $resolvedCorePath
Set-AutoVencordContext -BaseDir $installedBaseDir | Out-Null

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
    return @{
        Language = (Get-PreferredLanguageCode)
        BannerTitle = "AutoVencord"
        BannerHint = "Use Up/Down arrows to move, Enter to run, Esc to exit"
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
        DiscordIncomplete = "incomplete"
        DiscordUpdating = "updating"
        DiscordMissingInstalled = "Discord is missing. AutoVencord cannot work until Discord is installed."
        DiscordIncompleteMessage = "Discord looks incomplete or is still updating. Start Discord once, then try again."
        DiscordMissingInstall = "Install Discord before installing AutoVencord."
        Install = "Install"
        Update = "Update"
        Uninstall = "Uninstall"
        UninstallMenuTitle = "Uninstall"
        UninstallAutoVencord = "AutoVencord only"
        UninstallBoth = "AutoVencord + remove Vencord"
        Back = "Back"
        UninstallBothUnavailable = "Vencord can be removed only when Discord is ready and VencordInstallerCli.exe is available."
        UninstallingVencord = "Removing Vencord patch..."
        VencordUninstallDone = "Vencord patch removed."
        ClosingDiscord = "Closing Discord before removing the patch..."
        StoppingWatchdog = "Stopping AutoVencord Watchdog..."
        RestoringAsarBackup = "Restoring original app.asar from _app.asar..."
        VencordStillPatched = "Vencord is still detected after removing the patch."
        MissingAsarBackup = "Could not find _app.asar backup to restore Discord."
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
        ErrorInstall = "Installation failed."
        ErrorUpdate = "Update failed."
        ErrorPatch = "Discord patch failed."
        ErrorTask = "Failed to register watchdog."
        ErrorNetwork = "Failed to download AutoVencord payload."
        ErrorCli = "Failed to download or validate Vencord CLI."
    }
}

function Get-PayloadDefinition {
    $localManifest = Join-Path $scriptRoot "AutoVencord-Payload.json"
    if (Test-Path -LiteralPath $localManifest) {
        return (Read-JsonFile -Path $localManifest)
    }

    $download = Invoke-DownloadToFile -Urls (Get-PayloadCandidateUrls -FileName "AutoVencord-Payload.json") -DestinationPath $payloadManifestTempPath -MinBytes 32
    if (-not $download.Success) {
        throw "Failed to load payload manifest: $($download.Errors -join '; ')"
    }

    $manifest = Read-JsonFile -Path $payloadManifestTempPath
    if (-not $manifest) {
        throw "Payload manifest is invalid."
    }

    return $manifest
}

function Test-SetupPayload {
    param(
        [string]$Path,
        $PayloadDefinition
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    try {
        $content = Get-Content -LiteralPath $Path -Raw
        if (-not ($content.Contains('$payloadVersion') -and $content.Contains($AUTOVENCORD_PAYLOAD_VERSION))) {
            return $false
        }

        $expectedHashProperty = $PayloadDefinition.files.PSObject.Properties["AutoVencord-Setup.ps1"]
        if (-not $expectedHashProperty) {
            return $true
        }

        return ((Get-FileSha256 -Path $Path) -eq [string]$expectedHashProperty.Value)
    } catch {
        return $false
    }
}

function Download-LatestInstaller {
    param(
        [hashtable]$Ui,
        [switch]$AllowLocalFallback
    )

    $payloadDefinition = Get-PayloadDefinition
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
    Write-Host $Ui.Downloading -ForegroundColor Cyan

    $localSetupCandidate = Join-Path $scriptRoot "AutoVencord-Setup.ps1"
    if ($AllowLocalFallback -and (Test-Path -LiteralPath $localSetupCandidate) -and (Test-SetupPayload -Path $localSetupCandidate -PayloadDefinition $payloadDefinition)) {
        Copy-Item -LiteralPath $localSetupCandidate -Destination $setupPath -Force
        return [pscustomobject]@{
            SetupPath = $setupPath
            PayloadDefinition = $payloadDefinition
        }
    }

    $validation = {
        param($Path)
        Test-SetupPayload -Path $Path -PayloadDefinition $payloadDefinition
    }.GetNewClosure()

    $download = Invoke-DownloadToFile -Urls (Get-PayloadCandidateUrls -FileName "AutoVencord-Setup.ps1") -DestinationPath $setupPath -MinBytes 1024 -ValidationScript $validation
    if (-not $download.Success) {
        throw "Failed to download setup payload: $($download.Errors -join '; ')"
    }

    return [pscustomobject]@{
        SetupPath = $setupPath
        PayloadDefinition = $payloadDefinition
    }
}

function Get-StatusText {
    param(
        [hashtable]$Ui
    )

    $status = Get-AutoVencordStatus
    $installedValue = if ($status.Installed) { $Ui.Yes } else { $Ui.No }
    $watchdogState = $status.Watchdog

    if ($watchdogState.State -eq "WatchdogRunning") {
        $watchdogValue = "{0} ({1})" -f $Ui.Active, $watchdogState.RawState
    } elseif ($watchdogState.State -eq "WatchdogMissing") {
        $watchdogValue = $Ui.NotInstalled
    } elseif ($watchdogState.State -eq "WatchdogInstalled") {
        $watchdogValue = "{0} ({1})" -f $Ui.Inactive, $watchdogState.RawState
    } else {
        $watchdogValue = "{0} ({1})" -f $Ui.Unknown, $watchdogState.RawState
    }

    $discordValue = $null
    $discordMessage = $null
    switch ($status.Discord.State) {
        "DiscordMissing" {
            $discordValue = $Ui.DiscordMissing
            $discordMessage = if ($status.Installed) { $Ui.DiscordMissingInstalled } else { $Ui.DiscordMissingInstall }
        }
        "DiscordIncomplete" {
            $discordValue = $Ui.DiscordIncomplete
            $discordMessage = $Ui.DiscordIncompleteMessage
        }
        "DiscordUpdating" {
            $discordValue = $Ui.DiscordUpdating
            $discordMessage = $Ui.DiscordIncompleteMessage
        }
    }

    return [pscustomobject]@{
        InstalledLabel = $Ui.Installed
        InstalledValue = $installedValue
        InstalledOk = $status.Installed
        InstallFolderExists = (Test-Path -LiteralPath $installedBaseDir)
        WatchdogLabel = $Ui.Watchdog
        WatchdogValue = $watchdogValue
        WatchdogOk = ($watchdogState.State -eq "WatchdogRunning")
        DiscordLabel = $Ui.Discord
        DiscordState = $status.Discord.State
        DiscordValue = $discordValue
        DiscordMessage = $discordMessage
        Manifest = $status.Manifest
    }
}

function Test-InstalledPayloadMatches {
    param(
        $PayloadDefinition
    )

    $installedManifest = Get-InstalledPayloadManifest
    if (-not $installedManifest -or -not $PayloadDefinition) {
        return $false
    }

    if ([string]$installedManifest.version -ne [string]$PayloadDefinition.version) {
        return $false
    }

    foreach ($property in $PayloadDefinition.files.PSObject.Properties) {
        $installedProperty = $installedManifest.files.PSObject.Properties[$property.Name]
        if (-not $installedProperty) {
            continue
        }

        if ([string]$installedProperty.Value -ne [string]$property.Value) {
            return $false
        }
    }

    return $true
}

function Get-UpdateAvailability {
    param(
        [pscustomobject]$Status
    )

    if (-not $Status.InstalledOk) {
        return $false
    }

    try {
        $payloadDefinition = Get-PayloadDefinition
        return (-not (Test-InstalledPayloadMatches -PayloadDefinition $payloadDefinition))
    } catch {
        return $false
    }
}

function Get-MenuEnabledStates {
    param(
        [pscustomobject]$Status
    )

    if ($Status.DiscordState -ne "DiscordReady") {
        if ($Status.InstalledOk) {
            return @($false, $false, $true, $true, $true)
        }

        return @($false, $false, $Status.InstallFolderExists, $false, $true)
    }

    return @($true, $Status.InstalledOk, $true, $Status.InstalledOk, $true)
}

function Resolve-MenuIndex {
    param(
        [int]$InitialIndex,
        [bool[]]$EnabledStates
    )

    if ($InitialIndex -ge 0 -and $InitialIndex -lt $EnabledStates.Length -and $EnabledStates[$InitialIndex]) {
        return $InitialIndex
    }

    for ($i = 0; $i -lt $EnabledStates.Length; $i++) {
        if ($EnabledStates[$i]) {
            return $i
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

    if ($UpdateAvailable) {
        $script:UpdateStatusText = "{0}: {1}" -f $Ui.UpdateStatusLabel, $Ui.UpdateHintAvailable
        $script:UpdateOptionSuffix = $Ui.UpdateAvailableSuffix
        return
    }

    if ($Status.InstalledOk) {
        $script:UpdateStatusText = "{0}: {1}" -f $Ui.UpdateStatusLabel, $Ui.UpdateHintCurrent
        $script:UpdateOptionSuffix = ""
        return
    }

    $script:UpdateStatusText = "{0}: {1}" -f $Ui.UpdateStatusLabel, $Ui.UpdateHintUnavailable
    $script:UpdateOptionSuffix = ""
}

function Write-PaddedLine {
    param(
        [string]$Text = "",
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::Gray,
        [int]$Width = 80
    )

    $safeWidth = [Math]::Max(20, $Width)
    $trimmed = if ($Text.Length -gt $safeWidth) { $Text.Substring(0, $safeWidth) } else { $Text }
    Write-Host $trimmed.PadRight($safeWidth) -ForegroundColor $ForegroundColor
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
    Write-Host $trimmed.PadRight($safeWidth) -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor
}

function Clear-PendingConsoleInput {
    try {
        while ([Console]::KeyAvailable) {
            [Console]::ReadKey($true) | Out-Null
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
    Write-PaddedLine -Text $Ui.SectionTitle -ForegroundColor White -Width $width

    $installedColor = if ($Status.InstalledOk) { [ConsoleColor]::Green } else { [ConsoleColor]::DarkYellow }
    $watchdogColor = if ($Status.WatchdogOk) { [ConsoleColor]::Green } else { [ConsoleColor]::DarkYellow }
    Write-PaddedLine -Text ("{0}: {1}" -f $Status.InstalledLabel, $Status.InstalledValue) -ForegroundColor $installedColor -Width $width
    Write-PaddedLine -Text ("{0}: {1}" -f $Status.WatchdogLabel, $Status.WatchdogValue) -ForegroundColor $watchdogColor -Width $width

    if ($Status.DiscordValue) {
        Write-PaddedLine -Text ("{0}: {1}" -f $Status.DiscordLabel, $Status.DiscordValue) -ForegroundColor DarkYellow -Width $width
    } else {
        Write-PaddedLine -Text ("{0}: Ready" -f $Status.DiscordLabel) -ForegroundColor Green -Width $width
    }

    if ($Status.DiscordMessage) {
        Write-PaddedLine -Text $Status.DiscordMessage -ForegroundColor DarkYellow -Width $width
    } else {
        Write-PaddedLine -Text $script:UpdateStatusText -ForegroundColor DarkGray -Width $width
    }

    Write-PaddedLine -Text "" -Width $width

    for ($i = 0; $i -lt $Options.Length; $i++) {
        $label = $Options[$i]
        if ($i -eq 1) {
            $label += $script:UpdateOptionSuffix
        }

        $marker = if ($i -eq $SelectedIndex) { " >>" } else { "   " }
        $contentWidth = [Math]::Max(20, $width - $marker.Length)
        $left = ("  {0}" -f $label)
        if ($left.Length -gt $contentWidth) {
            $left = $left.Substring(0, $contentWidth)
        }

        $line = $left.PadRight($contentWidth) + $marker
        if (-not $EnabledStates[$i]) {
            Write-PaddedLine -Text $line -ForegroundColor DarkGray -Width $width
        } elseif ($i -eq $SelectedIndex) {
            Write-SelectedLine -Text $line -Width $width -ForegroundColor Black -BackgroundColor Cyan
        } else {
            Write-PaddedLine -Text $line -ForegroundColor White -Width $width
        }
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
    $updateAvailable = Get-UpdateAvailability -Status $status
    Set-UpdateMenuStatus -Status $status -Ui $Ui -UpdateAvailable $updateAvailable
    $enabledStates = Get-MenuEnabledStates -Status $status
    $index = Resolve-MenuIndex -InitialIndex $InitialIndex -EnabledStates $enabledStates

    try {
        $Host.UI.RawUI.WindowTitle = $windowTitle
    } catch {}

    Start-Sleep -Milliseconds 150
    Clear-PendingConsoleInput

    while ($true) {
        Render-Menu -Ui $Ui -Status $status -Options $Options -EnabledStates $enabledStates -SelectedIndex $index -FirstRender:$firstRender
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

        if ($key.VirtualKeyCode -eq 13 -and $enabledStates[$index]) {
            return $index
        }

        if ($key.VirtualKeyCode -eq 27) {
            return -1
        }
    }
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

    while ($true) {
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        if ($key.VirtualKeyCode -eq 13) { return $true }
        if ($key.VirtualKeyCode -eq 27) { return $false }
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

    Start-Sleep -Milliseconds 150
    Clear-PendingConsoleInput
    while ($true) {
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        if ($key.VirtualKeyCode -eq 13) { return $true }
        if ($key.VirtualKeyCode -eq 27) { return $false }
    }
}

function Assert-DiscordReady {
    param(
        [hashtable]$Ui
    )

    $discordState = (Get-AutoVencordStatus).Discord
    if ($discordState.State -eq "DiscordReady") {
        return
    }

    if ($discordState.State -eq "DiscordMissing") {
        throw $Ui.DiscordMissingInstall
    }

    throw $Ui.DiscordIncompleteMessage
}

function Get-SetupFailureMessage {
    param(
        [hashtable]$Ui,
        [int]$ExitCode
    )

    switch ($ExitCode) {
        10 { return $Ui.ErrorNetwork }
        20 { return $Ui.DiscordMissingInstall }
        21 { return $Ui.DiscordIncompleteMessage }
        30 { return $Ui.ErrorCli }
        40 { return $Ui.ErrorPatch }
        50 { return $Ui.ErrorTask }
        default { return $Ui.ErrorInstall }
    }
}

function Invoke-SetupScript {
    param(
        [string]$SetupScriptPath,
        [switch]$PatchNow,
        [hashtable]$Ui
    )

    $oldSkipSelfUpdate = $env:AUTOVENCORD_SKIP_SELF_UPDATE
    $oldNoPause = $env:AUTOVENCORD_NO_PAUSE
    $sourceBatch = Join-Path $scriptRoot "AutoVencord-OneClick.bat"
    $sourceCore = Join-Path $scriptRoot "AutoVencord.Core.ps1"
    $sourcePayloadManifest = Join-Path $scriptRoot "AutoVencord-Payload.json"

    try {
        $env:AUTOVENCORD_SKIP_SELF_UPDATE = "1"
        $env:AUTOVENCORD_NO_PAUSE = "1"
        $setupArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $SetupScriptPath, "-SourceSetupPath", $SetupScriptPath)

        if (Test-Path -LiteralPath $sourceBatch) {
            $setupArgs += @("-SourceBatPath", $sourceBatch)
        }

        if (Test-Path -LiteralPath $sourceCore) {
            $setupArgs += @("-SourceCorePath", $sourceCore)
        }

        if (Test-Path -LiteralPath $sourcePayloadManifest) {
            $setupArgs += @("-SourcePayloadManifestPath", $sourcePayloadManifest)
        }

        if ($PatchNow) {
            $setupArgs += "-PatchNow"
        }

        & powershell.exe @setupArgs
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            throw (Get-SetupFailureMessage -Ui $Ui -ExitCode $exitCode)
        }
    } finally {
        $env:AUTOVENCORD_SKIP_SELF_UPDATE = $oldSkipSelfUpdate
        $env:AUTOVENCORD_NO_PAUSE = $oldNoPause
    }
}

function Invoke-Install {
    param(
        [hashtable]$Ui
    )

    Assert-DiscordReady -Ui $Ui
    $downloaded = Download-LatestInstaller -Ui $Ui -AllowLocalFallback
    Invoke-SetupScript -SetupScriptPath $downloaded.SetupPath -PatchNow -Ui $Ui
}

function Stop-AutoVencordWatchdogForUninstall {
    param(
        [hashtable]$Ui
    )

    Write-Host $Ui.StoppingWatchdog -ForegroundColor Yellow
    Stop-AutoVencordTask

    try {
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                ($_.Name -in @("powershell.exe", "pwsh.exe")) -and
                $_.CommandLine -like "*watchdog.ps1*"
            } |
            Where-Object { $_.ProcessId -ne $PID } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    } catch {}

    Start-Sleep -Seconds 1
}

function Stop-DiscordForVencordUninstall {
    param(
        [hashtable]$Ui
    )

    Write-Host $Ui.ClosingDiscord -ForegroundColor Yellow
    Get-Process Discord -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $deadline = (Get-Date).AddSeconds(20)

    while ((Get-Date) -lt $deadline) {
        if (-not (Get-Process Discord -ErrorAction SilentlyContinue)) {
            return
        }

        Start-Sleep -Milliseconds 500
    }
}

function Restore-DiscordAsarBackupIfNeeded {
    param(
        [hashtable]$Ui
    )

    $discordState = Get-DiscordState
    if (-not $discordState.Latest) {
        return
    }

    $resources = Join-Path $discordState.Latest.FullName "resources"
    $appAsar = Join-Path $resources "app.asar"
    $backupAsar = Join-Path $resources "_app.asar"
    $patchState = Get-PatchState -AppDir $discordState.Latest

    if (($patchState.State -eq "PatchMissing") -and -not (Test-Path -LiteralPath $backupAsar)) {
        return
    }

    if (-not (Test-Path -LiteralPath $backupAsar)) {
        throw $Ui.MissingAsarBackup
    }

    Write-Host $Ui.RestoringAsarBackup -ForegroundColor Yellow
    Copy-Item -LiteralPath $backupAsar -Destination $appAsar -Force
    Remove-Item -LiteralPath $backupAsar -Force -ErrorAction SilentlyContinue

    $verifiedState = Get-PatchState -AppDir (Get-DiscordState).Latest
    if ($verifiedState.State -eq "PatchPresent") {
        throw $Ui.VencordStillPatched
    }
}

function Test-CanUninstallVencordPatch {
    $status = Get-AutoVencordStatus
    $context = Get-AutoVencordContext
    return ((Test-Path -LiteralPath $context.InstallerPath) -and $status.Discord.State -eq "DiscordReady")
}

function Render-UninstallMenu {
    param(
        [hashtable]$Ui,
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
    Write-PaddedLine -Text $Ui.UninstallMenuTitle -ForegroundColor Red -Width $width
    Write-PaddedLine -Text "" -Width $width

    if (-not $EnabledStates[1]) {
        Write-PaddedLine -Text $Ui.UninstallBothUnavailable -ForegroundColor DarkYellow -Width $width
        Write-PaddedLine -Text "" -Width $width
    }

    for ($i = 0; $i -lt $Options.Length; $i++) {
        $marker = if ($i -eq $SelectedIndex) { " >>" } else { "   " }
        $contentWidth = [Math]::Max(20, $width - $marker.Length)
        $left = ("  {0}" -f $Options[$i])
        if ($left.Length -gt $contentWidth) {
            $left = $left.Substring(0, $contentWidth)
        }

        $line = $left.PadRight($contentWidth) + $marker
        if (-not $EnabledStates[$i]) {
            Write-PaddedLine -Text $line -ForegroundColor DarkGray -Width $width
        } elseif ($i -eq $SelectedIndex) {
            Write-SelectedLine -Text $line -Width $width -ForegroundColor White -BackgroundColor Red
        } else {
            Write-PaddedLine -Text $line -ForegroundColor Red -Width $width
        }
    }
}

function Show-UninstallMenu {
    param(
        [hashtable]$Ui
    )

    $options = @($Ui.UninstallAutoVencord, $Ui.UninstallBoth, $Ui.Back)
    $enabledStates = @($true, (Test-CanUninstallVencordPatch), $true)
    $index = Resolve-MenuIndex -InitialIndex 0 -EnabledStates $enabledStates
    $firstRender = $true

    while ($true) {
        Render-UninstallMenu -Ui $Ui -Options $options -EnabledStates $enabledStates -SelectedIndex $index -FirstRender:$firstRender
        $firstRender = $false
        Clear-PendingConsoleInput
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

        if ($key.VirtualKeyCode -eq 27) {
            return 2
        }

        if ($key.VirtualKeyCode -eq 13 -and $enabledStates[$index]) {
            return $index
        }

        if ($key.VirtualKeyCode -eq 38) {
            for ($i = $index - 1; $i -ge 0; $i--) {
                if ($enabledStates[$i]) {
                    $index = $i
                    break
                }
            }
        } elseif ($key.VirtualKeyCode -eq 40) {
            for ($i = $index + 1; $i -lt $options.Length; $i++) {
                if ($enabledStates[$i]) {
                    $index = $i
                    break
                }
            }
        }
    }
}

function Invoke-VencordPatchUninstall {
    param(
        [hashtable]$Ui
    )

    Assert-DiscordReady -Ui $Ui
    $context = Get-AutoVencordContext
    if (-not (Test-Path -LiteralPath $context.InstallerPath)) {
        throw $Ui.UninstallBothUnavailable
    }

    Stop-AutoVencordWatchdogForUninstall -Ui $Ui
    Stop-DiscordForVencordUninstall -Ui $Ui
    Write-Host $Ui.UninstallingVencord -ForegroundColor Yellow

    $result = Invoke-VencordCliAction -InstallerPath $context.InstallerPath -Action "uninstall" -DiscordRoot $context.DiscordRoot -TimeoutSeconds 180 -LogPhase "UNINSTALL"
    $combinedOutput = ($result.Output -join "`n")
    $reportedSuccess = ($combinedOutput -match "Successfully unpatched" -or $combinedOutput -match "Success")

    if ($combinedOutput) {
        Write-Host $combinedOutput.TrimEnd()
    }

    if (-not $result.Success -and -not $reportedSuccess) {
        throw "Vencord CLI uninstall failed with exit code $($result.ExitCode)."
    }

    Restore-DiscordAsarBackupIfNeeded -Ui $Ui
    Write-Host $Ui.VencordUninstallDone -ForegroundColor Green
}

function Invoke-Uninstall {
    param(
        [hashtable]$Ui
    )

    $context = Get-AutoVencordContext
    if (-not (Test-Path -LiteralPath $context.UninstallPath)) {
        Write-Host $Ui.MissingUninstall -ForegroundColor Yellow
        return
    }

    Write-Host $Ui.RunningUninstall -ForegroundColor Yellow
    $oldNoPause = $env:AUTOVENCORD_NO_PAUSE
    try {
        $env:AUTOVENCORD_NO_PAUSE = "1"
        & $context.UninstallPath
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
    $downloaded = Download-LatestInstaller -Ui $Ui -AllowLocalFallback

    if (Test-InstalledPayloadMatches -PayloadDefinition $downloaded.PayloadDefinition) {
        Write-Host $Ui.AlreadyLatest -ForegroundColor Green
        return $false
    }

    Invoke-SetupScript -SetupScriptPath $downloaded.SetupPath -PatchNow -Ui $Ui
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
    try {
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
            if (-not $autoAction) {
                $uninstallSelection = Show-UninstallMenu -Ui $ui
                $selectedIndex = 3
                if ($uninstallSelection -eq 2) {
                    continue
                }

                Clear-Host
                if ($uninstallSelection -eq 1) {
                    Invoke-VencordPatchUninstall -Ui $ui
                }
            }

            Invoke-Uninstall -Ui $ui
            if (-not $autoAction) {
                if (Show-ActionResult -Ui $ui -Message $ui.UninstallDone -Color Green) {
                    continue
                }
            }
        }
    } catch {
        $message = $_.Exception.Message
        if (-not $autoAction) {
            if (Show-ActionResult -Ui $ui -Message $message -Color Red) {
                continue
            }
        } else {
            throw
        }
    }

    break
}
