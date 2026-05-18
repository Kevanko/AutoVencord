$ErrorActionPreference = "Stop"

$AUTOVENCORD_PAYLOAD_VERSION = "2026.05.18.8"
$installerPayloadRef = if ($env:AUTOVENCORD_PAYLOAD_REF) { $env:AUTOVENCORD_PAYLOAD_REF } else { "main" }
$installerPayloadMarker = "AUTOVENCORD_PAYLOAD_VERSION"
$windowTitle = "AutoVencord"
$scriptRoot = if ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PWD.Path }
$tempDir = Join-Path $env:TEMP "AutoVencord"
$setupPath = Join-Path $tempDir "AutoVencord-Setup.ps1"
$payloadManifestTempPath = Join-Path $tempDir "AutoVencord-Payload.json"
$coreTempPath = Join-Path $tempDir "AutoVencord.Core.ps1"
$installedBaseDir = Join-Path $env:LOCALAPPDATA "AutoVencord"
$script:CachedPayloadDefinition = $null
$script:CachedUpdateAvailability = $null
$script:CachedUpdateAvailabilityVersion = $null
$script:CachedUpdateAvailabilityInstalledAt = $null

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
                Invoke-WebRequest -UseBasicParsing $url -OutFile $tempPath -TimeoutSec 15
            } else {
                $client = New-Object System.Net.WebClient
                $client.Headers.Add("user-agent", "AutoVencord")
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

function Get-CoreModuleScriptBlock {
    param(
        [string]$Path
    )

    $content = Get-Content -LiteralPath $Path -Raw
    return [scriptblock]::Create($content)
}

$resolvedCorePath = Initialize-CoreModule
$resolvedCoreScriptBlock = Get-CoreModuleScriptBlock -Path $resolvedCorePath
. $resolvedCoreScriptBlock
Set-AutoVencordContext -BaseDir $installedBaseDir | Out-Null

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
            DiscordIncomplete = Join-CodePoints @(1085,1077,1087,1086,1083,1085,1072,1103,32,1091,1089,1090,1072,1085,1086,1074,1082,1072)
            DiscordUpdating = Join-CodePoints @(1086,1073,1085,1086,1074,1083,1103,1077,1090,1089,1103)
            DiscordMissingInstalled = Join-CodePoints @(68,105,115,99,111,114,100,32,1085,1077,32,1085,1072,1081,1076,1077,1085,46,32,65,117,116,111,86,101,110,99,111,114,100,32,1085,1077,32,1089,1084,1086,1078,1077,1090,32,1088,1072,1073,1086,1090,1072,1090,1100,44,32,1087,1086,1082,1072,32,68,105,115,99,111,114,100,32,1085,1077,32,1091,1089,1090,1072,1085,1086,1074,1083,1077,1085,46)
            DiscordIncompleteMessage = Join-CodePoints @(68,105,115,99,111,114,100,32,1074,1099,1075,1083,1103,1076,1080,1090,32,1085,1077,1087,1086,1083,1085,1086,32,1080,1083,1080,32,1077,1097,1077,32,1086,1073,1085,1086,1074,1083,1103,1077,1090,1089,1103,46,32,1047,1072,1087,1091,1089,1090,1080,32,68,105,115,99,111,114,100,32,1086,1076,1080,1085,32,1088,1072,1079,32,1080,32,1087,1086,1074,1090,1086,1088,1080,46)
            DiscordMissingInstall = Join-CodePoints @(1059,1089,1090,1072,1085,1086,1074,1080,32,68,105,115,99,111,114,100,32,1087,1077,1088,1077,1076,32,1091,1089,1090,1072,1085,1086,1074,1082,1086,1081,32,65,117,116,111,86,101,110,99,111,114,100,46)
            Install = Join-CodePoints @(1059,1089,1090,1072,1085,1086,1074,1080,1090,1100)
            Update = Join-CodePoints @(1054,1073,1085,1086,1074,1080,1090,1100)
            Uninstall = Join-CodePoints @(1059,1076,1072,1083,1080,1090,1100)
            UninstallMenuTitle = Join-CodePoints @(1059,1076,1072,1083,1077,1085,1080,1077)
            UninstallAutoVencord = Join-CodePoints @(1058,1086,1083,1100,1082,1086,32,65,117,116,111,86,101,110,99,111,114,100)
            UninstallBoth = Join-CodePoints @(65,117,116,111,86,101,110,99,111,114,100,32,43,32,1089,1085,1103,1090,1100,32,86,101,110,99,111,114,100)
            Back = Join-CodePoints @(1053,1072,1079,1072,1076)
            UninstallBothUnavailable = Join-CodePoints @(86,101,110,99,111,114,100,32,1084,1086,1078,1085,1086,32,1091,1076,1072,1083,1080,1090,1100,32,1090,1086,1083,1100,1082,1086,32,1082,1086,1075,1076,1072,32,68,105,115,99,111,114,100,32,1075,1086,1090,1086,1074,32,1080,32,1076,1086,1089,1090,1091,1087,1077,1085,32,86,101,110,99,111,114,100,73,110,115,116,97,108,108,101,114,67,108,105,46,101,120,101,46)
            UninstallingVencord = Join-CodePoints @(1057,1085,1080,1084,1072,1102,32,1087,1072,1090,1095,32,86,101,110,99,111,114,100,46,46,46)
            VencordUninstallDone = Join-CodePoints @(1055,1072,1090,1095,32,86,101,110,99,111,114,100,32,1089,1085,1103,1090,46)
            ClosingDiscord = Join-CodePoints @(1047,1072,1082,1088,1099,1074,1072,1102,32,68,105,115,99,111,114,100,32,1087,1077,1088,1077,1076,32,1089,1085,1103,1090,1080,1077,1084,32,1087,1072,1090,1095,1072,46,46,46)
            StoppingWatchdog = Join-CodePoints @(1054,1089,1090,1072,1085,1072,1074,1083,1080,1074,1072,1102,32,65,117,116,111,86,101,110,99,111,114,100,32,87,97,116,99,104,100,111,103,46,46,46)
            RestoringAsarBackup = Join-CodePoints @(1042,1086,1089,1089,1090,1072,1085,1072,1074,1083,1080,1074,1072,1102,32,1080,1089,1093,1086,1076,1085,1099,1081,32,97,112,112,46,97,115,97,114,32,1080,1079,32,95,97,112,112,46,97,115,97,114,46,46,46)
            VencordStillPatched = Join-CodePoints @(86,101,110,99,111,114,100,32,1074,1089,1077,32,1077,1097,1077,32,1086,1087,1088,1077,1076,1077,1083,1103,1077,1090,1089,1103,32,1087,1086,1089,1083,1077,32,1091,1076,1072,1083,1077,1085,1080,1103,32,1087,1072,1090,1095,1072,46)
            MissingAsarBackup = Join-CodePoints @(1053,1077,32,1085,1072,1081,1076,1077,1085,32,95,97,112,112,46,97,115,97,114,32,1076,1083,1103,32,1074,1086,1089,1089,1090,1072,1085,1086,1074,1083,1077,1085,1080,1103,32,68,105,115,99,111,114,100,46)
            OpenFolder = Join-CodePoints @(1054,1090,1082,1088,1099,1090,1100,32,1087,1072,1087,1082,1091)
            Exit = Join-CodePoints @(1042,1099,1093,1086,1076)
            Downloading = Join-CodePoints @(1057,1082,1072,1095,1080,1074,1072,1102,32,1072,1082,1090,1091,1072,1083,1100,1085,1099,1081,32,1091,1089,1090,1072,1085,1086,1074,1097,1080,1082,32,65,117,116,111,86,101,110,99,111,114,100,46,46,46)
            Updating = Join-CodePoints @(1054,1073,1085,1086,1074,1083,1103,1102,32,65,117,116,111,86,101,110,99,111,114,100,46,46,46)
            RunningUninstall = Join-CodePoints @(1047,1072,1087,1091,1089,1082,1072,1102,32,1091,1076,1072,1083,1077,1085,1080,1077,32,65,117,116,111,86,101,110,99,111,114,100,46,46,46)
            MissingUninstall = Join-CodePoints @(65,117,116,111,86,101,110,99,111,114,100,32,1085,1077,32,1091,1089,1090,1072,1085,1086,1074,1083,1077,1085,46)
            AlreadyLatest = Join-CodePoints @(1059,32,1090,1077,1073,1103,32,1091,1078,1077,32,1087,1086,1089,1083,1077,1076,1085,1103,1103,32,1074,1077,1088,1089,1080,1103,46)
            ConfirmInstallTitle = Join-CodePoints @(1042,1099,1073,1088,1072,1085,1072,32,1091,1089,1090,1072,1085,1086,1074,1082,1072,46)
            ConfirmInstallEnter = Join-CodePoints @(1053,1072,1078,1084,1080,32,69,110,116,101,114,32,1077,1097,1077,32,1088,1072,1079,44,32,1095,1090,1086,1073,1099,32,1087,1086,1076,1090,1074,1077,1088,1076,1080,1090,1100,32,1091,1089,1090,1072,1085,1086,1074,1082,1091,46)
            ConfirmInstallEsc = Join-CodePoints @(1053,1072,1078,1084,1080,32,69,115,99,44,32,1095,1090,1086,1073,1099,32,1074,1077,1088,1085,1091,1090,1100,1089,1103,32,1085,1072,1079,1072,1076,46)
            InstallDone = Join-CodePoints @(1059,1089,1090,1072,1085,1086,1074,1082,1072,32,1079,1072,1074,1077,1088,1096,1077,1085,1072,46)
            UpdateDone = Join-CodePoints @(1054,1073,1085,1086,1074,1083,1077,1085,1080,1077,32,1079,1072,1074,1077,1088,1096,1077,1085,1086,46)
            UninstallDone = Join-CodePoints @(1059,1076,1072,1083,1077,1085,1080,1077,32,1079,1072,1074,1077,1088,1096,1077,1085,1086,46)
            ResultHint = Join-CodePoints @(1053,1072,1078,1084,1080,32,69,110,116,101,114,32,45,32,1074,1077,1088,1085,1091,1090,1100,1089,1103,32,1074,32,1084,1077,1085,1102,44,32,69,115,99,32,45,32,1074,1099,1081,1090,1080,46)
            UpdateAvailableSuffix = " *"
            UpdateStatusLabel = Join-CodePoints @(1054,1073,1085,1086,1074,1083,1077,1085,1080,1077)
            UpdateAvailable = Join-CodePoints @(1044,1086,1089,1090,1091,1087,1085,1086)
            UpdateCurrent = Join-CodePoints @(1040,1082,1090,1091,1072,1083,1100,1085,1086)
            UpdateUnavailable = Join-CodePoints @(1053,1077,1076,1086,1089,1090,1091,1087,1085,1086)
            UpdateHintAvailable = Join-CodePoints @(1084,1086,1078,1085,1086,32,1086,1073,1085,1086,1074,1080,1090,1100)
            UpdateHintCurrent = Join-CodePoints @(1072,1082,1090,1091,1072,1083,1100,1085,1086)
            UpdateHintUnavailable = Join-CodePoints @(1085,1077,32,1091,1089,1090,1072,1085,1086,1074,1083,1077,1085)
            ErrorInstall = Join-CodePoints @(1059,1089,1090,1072,1085,1086,1074,1082,1072,32,1085,1077,32,1091,1076,1072,1083,1072,1089,1100,46)
            ErrorUpdate = Join-CodePoints @(1054,1073,1085,1086,1074,1083,1077,1085,1080,1077,32,1085,1077,32,1091,1076,1072,1083,1086,1089,1100,46)
            ErrorPatch = Join-CodePoints @(1055,1072,1090,1095,32,68,105,115,99,111,114,100,32,1085,1077,32,1091,1076,1072,1083,1089,1103,46)
            ErrorTask = Join-CodePoints @(1053,1077,32,1091,1076,1072,1083,1086,1089,1100,32,1079,1072,1088,1077,1075,1080,1089,1090,1088,1080,1088,1086,1074,1072,1090,1100,32,119,97,116,99,104,100,111,103,46)
            ErrorNetwork = Join-CodePoints @(1053,1077,32,1091,1076,1072,1083,1086,1089,1100,32,1089,1082,1072,1095,1072,1090,1100,32,112,97,121,108,111,97,100,32,65,117,116,111,86,101,110,99,111,114,100,46)
            ErrorCli = Join-CodePoints @(1053,1077,32,1091,1076,1072,1083,1086,1089,1100,32,1089,1082,1072,1095,1072,1090,1100,32,1080,1083,1080,32,1087,1088,1086,1074,1077,1088,1080,1090,1100,32,86,101,110,99,111,114,100,32,67,76,73,46)
        }
    }

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
    if ($script:CachedPayloadDefinition) {
        return $script:CachedPayloadDefinition
    }

    $localManifest = Join-Path $scriptRoot "AutoVencord-Payload.json"
    if (Test-Path -LiteralPath $localManifest) {
        $script:CachedPayloadDefinition = Read-JsonFile -Path $localManifest
        return $script:CachedPayloadDefinition
    }

    $download = Invoke-DownloadToFile -Urls (Get-PayloadCandidateUrls -FileName "AutoVencord-Payload.json") -DestinationPath $payloadManifestTempPath -MinBytes 32
    if (-not $download.Success) {
        throw "Failed to load payload manifest: $($download.Errors -join '; ')"
    }

    $manifest = Read-JsonFile -Path $payloadManifestTempPath
    if (-not $manifest) {
        throw "Payload manifest is invalid."
    }

    $script:CachedPayloadDefinition = $manifest
    return $script:CachedPayloadDefinition
}

function Get-LocalPayloadDefinition {
    if ($script:CachedPayloadDefinition) {
        return $script:CachedPayloadDefinition
    }

    $localManifest = Join-Path $scriptRoot "AutoVencord-Payload.json"
    if (-not (Test-Path -LiteralPath $localManifest)) {
        return $null
    }

    $script:CachedPayloadDefinition = Read-JsonFile -Path $localManifest
    return $script:CachedPayloadDefinition
}

function Reset-UpdateAvailabilityCache {
    $script:CachedUpdateAvailability = $null
    $script:CachedUpdateAvailabilityVersion = $null
    $script:CachedUpdateAvailabilityInstalledAt = $null
}

function Convert-PayloadVersion {
    param(
        [string]$Value
    )

    try {
        return [version]$Value
    } catch {
        return [version]"0.0.0.0"
    }
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

    $localSetupCandidate = Join-Path $scriptRoot "AutoVencord-Setup.ps1"
    if ($AllowLocalFallback -and (Test-Path -LiteralPath $localSetupCandidate) -and (Test-SetupPayload -Path $localSetupCandidate -PayloadDefinition $payloadDefinition)) {
        Copy-Item -LiteralPath $localSetupCandidate -Destination $setupPath -Force
        return [pscustomobject]@{
            SetupPath = $setupPath
            PayloadDefinition = $payloadDefinition
        }
    }

    Write-Host $Ui.Downloading -ForegroundColor Cyan

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

    $status = Get-AutoVencordStatus -Fast
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
        $installedManifest = $Status.Manifest
        if (-not $installedManifest) {
            return $false
        }

        $installedVersion = [string]$installedManifest.version
        $installedAt = [string]$installedManifest.installedAt
        if (($script:CachedUpdateAvailability -ne $null) -and
            $script:CachedUpdateAvailabilityVersion -eq $installedVersion -and
            $script:CachedUpdateAvailabilityInstalledAt -eq $installedAt) {
            return [bool]$script:CachedUpdateAvailability
        }

        $currentVersion = Convert-PayloadVersion -Value $AUTOVENCORD_PAYLOAD_VERSION
        $installedParsedVersion = Convert-PayloadVersion -Value $installedVersion
        $script:CachedUpdateAvailability = ($currentVersion -gt $installedParsedVersion)

        $script:CachedUpdateAvailabilityVersion = $installedVersion
        $script:CachedUpdateAvailabilityInstalledAt = $installedAt
        return [bool]$script:CachedUpdateAvailability
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
        $script:UpdateStatusColor = [ConsoleColor]::Yellow
        $script:UpdateOptionSuffix = $Ui.UpdateAvailableSuffix
        return
    }

    if ($Status.InstalledOk) {
        $script:UpdateStatusText = "{0}: {1}" -f $Ui.UpdateStatusLabel, $Ui.UpdateHintCurrent
        $script:UpdateStatusColor = [ConsoleColor]::DarkGray
        $script:UpdateOptionSuffix = ""
        return
    }

    $script:UpdateStatusText = "{0}: {1}" -f $Ui.UpdateStatusLabel, $Ui.UpdateHintUnavailable
    $script:UpdateStatusColor = [ConsoleColor]::DarkGray
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
        $updateStatusColor = if ($script:UpdateStatusColor) { $script:UpdateStatusColor } else { [ConsoleColor]::DarkGray }
        Write-PaddedLine -Text $script:UpdateStatusText -ForegroundColor $updateStatusColor -Width $width
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
        $lineColor = [ConsoleColor]::White
        $selectedBackground = [ConsoleColor]::Cyan
        $selectedForeground = [ConsoleColor]::Black

        if ($i -eq 1 -and $script:UpdateOptionSuffix) {
            $lineColor = [ConsoleColor]::Yellow
            $selectedBackground = [ConsoleColor]::Yellow
        } elseif ($i -eq 3) {
            $lineColor = [ConsoleColor]::Red
            $selectedBackground = [ConsoleColor]::Red
            $selectedForeground = [ConsoleColor]::White
        }

        if (-not $EnabledStates[$i]) {
            Write-PaddedLine -Text $line -ForegroundColor DarkGray -Width $width
        } elseif ($i -eq $SelectedIndex) {
            Write-SelectedLine -Text $line -Width $width -ForegroundColor $selectedForeground -BackgroundColor $selectedBackground
        } else {
            Write-PaddedLine -Text $line -ForegroundColor $lineColor -Width $width
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

    Clear-PendingConsoleInput
    while ($true) {
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        if ($key.VirtualKeyCode -eq 13) { return $true }
        if ($key.VirtualKeyCode -eq 27) { return $false }
    }
}

function Assert-DiscordReady {
    param(
        [hashtable]$Ui,
        [switch]$AllowBusy
    )

    $discordState = (Get-AutoVencordStatus).Discord
    if ($discordState.State -eq "DiscordReady") {
        return
    }

    if ($AllowBusy -and $discordState.State -in @("DiscordUpdating", "DiscordIncomplete")) {
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

    Assert-DiscordReady -Ui $Ui -AllowBusy
    $downloaded = Download-LatestInstaller -Ui $Ui -AllowLocalFallback
    Invoke-SetupScript -SetupScriptPath $downloaded.SetupPath -PatchNow -Ui $Ui
    Reset-UpdateAvailabilityCache
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

    $pathsToRemove = @(
        $context.WatchdogPath,
        $context.CorePath,
        $context.InstallerPath,
        $context.BatchPath,
        $context.SetupPath,
        $context.PayloadManifestPath,
        (Join-Path $context.BaseDir "AutoVencord-Setup.sha256"),
        $context.RuntimeManifestPath,
        $context.UninstallPath,
        $context.LogPath,
        $context.PreviousLogPath
    )

    foreach ($path in $pathsToRemove) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }

    Remove-Item -LiteralPath $context.BaseDir -Force -Recurse -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $context.BaseDir) {
        $runtimeLeft = Get-ChildItem -LiteralPath $context.BaseDir -Force -ErrorAction SilentlyContinue
        if ($runtimeLeft.Count -gt 0) {
            throw "AutoVencord uninstaller could not remove all files."
        }
    }

    Reset-UpdateAvailabilityCache
}

function Invoke-Update {
    param(
        [hashtable]$Ui
    )

    Assert-DiscordReady -Ui $Ui -AllowBusy
    $status = Get-StatusText -Ui $Ui
    if (-not (Get-UpdateAvailability -Status $status)) {
        Reset-UpdateAvailabilityCache
        Write-Host $Ui.AlreadyLatest -ForegroundColor Green
        return $false
    }

    Write-Host $Ui.Updating -ForegroundColor Cyan
    $downloaded = Download-LatestInstaller -Ui $Ui -AllowLocalFallback

    if (Test-InstalledPayloadMatches -PayloadDefinition $downloaded.PayloadDefinition) {
        Reset-UpdateAvailabilityCache
        Write-Host $Ui.AlreadyLatest -ForegroundColor Green
        return $false
    }

    Invoke-SetupScript -SetupScriptPath $downloaded.SetupPath -PatchNow -Ui $Ui
    Reset-UpdateAvailabilityCache
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
                continue
            }
        } elseif ($selection -eq 1) {
            $null = Invoke-Update -Ui $ui
            if (-not $autoAction) {
                continue
            }
        } elseif ($selection -eq 3) {
            $uninstallCompleted = $false
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
            $uninstallCompleted = $true
            if (-not $autoAction) {
                if ($uninstallCompleted -and (Show-ActionResult -Ui $ui -Message $ui.UninstallDone -Color Green)) {
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
