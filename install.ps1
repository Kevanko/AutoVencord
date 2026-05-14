$ErrorActionPreference = "Stop"

$installerUrl = "https://raw.githubusercontent.com/Kevanko/AutoVencord/main/AutoVencord-OneClick.bat"
$tempDir = Join-Path $env:TEMP "AutoVencord"
$batPath = Join-Path $tempDir "AutoVencord-OneClick.bat"
$installedBaseDir = Join-Path $env:LOCALAPPDATA "AutoVencord"
$installedInstallerPath = Join-Path $installedBaseDir "AutoVencord-OneClick.bat"
$uninstallPath = Join-Path $installedBaseDir "uninstall.bat"
$watchdogScriptPath = Join-Path $installedBaseDir "watchdog.ps1"
$installedCliPath = Join-Path $installedBaseDir "VencordInstallerCli.exe"
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
            BannerHint = Join-CodePoints @(1057,1090,1088,1077,1083,1082,1080,32,1074,1074,1077,1088,1093,47,1074,1085,1080,1079,32,45,32,1074,1099,1073,1086,1088,44,32,69,110,116,101,114,32,45,32,1079,1072,1087,1091,1089,1082)
            SectionTitle = Join-CodePoints @(1059,1089,1090,1072,1085,1086,1074,1082,1072,32,1080,32,1086,1073,1089,1083,1091,1078,1080,1074,1072,1085,1080,1077)
            Installed = Join-CodePoints @(1059,1089,1090,1072,1085,1086,1074,1083,1077,1085,1086)
            Yes = Join-CodePoints @(1044,1072)
            No = Join-CodePoints @(1053,1077,1090)
            Watchdog = "Watchdog"
            Active = Join-CodePoints @(1040,1082,1090,1080,1074,1077,1085)
            Inactive = Join-CodePoints @(1053,1077,1072,1082,1090,1080,1074,1077,1085)
            NotInstalled = Join-CodePoints @(1053,1077,32,1091,1089,1090,1072,1085,1086,1074,1083,1077,1085)
            Unknown = Join-CodePoints @(1053,1077,1080,1079,1074,1077,1089,1090,1085,1086)
            Install = Join-CodePoints @(1059,1089,1090,1072,1085,1086,1074,1080,1090,1100)
            Update = Join-CodePoints @(1054,1073,1085,1086,1074,1080,1090,1100)
            Uninstall = Join-CodePoints @(1059,1076,1072,1083,1080,1090,1100)
            OpenFolder = Join-CodePoints @(1054,1090,1082,1088,1099,1090,1100,32,1087,1072,1087,1082,1091)
            Downloading = Join-CodePoints @(1057,1082,1072,1095,1080,1074,1072,1102,32,1072,1082,1090,1091,1072,1083,1100,1085,1099,1081,32,1091,1089,1090,1072,1085,1086,1074,1097,1080,1082,32,65,117,116,111,86,101,110,99,111,114,100,46,46,46)
            Updating = Join-CodePoints @(1054,1073,1085,1086,1074,1083,1103,1102,32,65,117,116,111,86,101,110,99,111,114,100,46,46,46)
            RunningUninstall = Join-CodePoints @(1047,1072,1087,1091,1089,1082,1072,1102,32,1091,1076,1072,1083,1077,1085,1080,1077,32,65,117,116,111,86,101,110,99,111,114,100,46,46,46)
            MissingUninstall = Join-CodePoints @(65,117,116,111,86,101,110,99,111,114,100,32,1085,1077,32,1091,1089,1090,1072,1085,1086,1074,1083,1077,1085,46)
            AlreadyLatest = Join-CodePoints @(1059,32,1074,1072,1089,32,1072,1082,1090,1091,1072,1083,1100,1085,1072,1103,32,1074,1077,1088,1089,1080,1103,46)
            ConfirmInstallTitle = Join-CodePoints @(1042,1099,1073,1088,1072,1085,1072,32,1091,1089,1090,1072,1085,1086,1074,1082,1072,46)
            ConfirmInstallEnter = Join-CodePoints @(1053,1072,1078,1084,1080,32,69,110,116,101,114,32,1077,1097,1077,32,1088,1072,1079,32,1076,1083,1103,32,1087,1086,1076,1090,1074,1077,1088,1078,1076,1077,1085,1080,1103,46)
            ConfirmInstallEsc = Join-CodePoints @(1053,1072,1078,1084,1080,32,69,115,99,44,32,1095,1090,1086,1073,1099,32,1074,1077,1088,1085,1091,1090,1100,1089,1103,32,1085,1072,1079,1072,1076,46)
            UpdateAvailableSuffix = " *"
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
        Active = "Active"
        Inactive = "Inactive"
        NotInstalled = "Not installed"
        Unknown = "Unknown"
        Install = "Install"
        Update = "Update"
        Uninstall = "Uninstall"
        OpenFolder = "Open Folder"
        Downloading = "Downloading latest AutoVencord installer..."
        Updating = "Updating AutoVencord..."
        RunningUninstall = "Running AutoVencord uninstaller..."
        MissingUninstall = "AutoVencord is not installed."
        AlreadyLatest = "You already have the latest version."
        ConfirmInstallTitle = "Install selected."
        ConfirmInstallEnter = "Press Enter again to confirm installation."
        ConfirmInstallEsc = "Press Esc to go back."
        UpdateAvailableSuffix = " *"
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

function Get-StatusText {
    param(
        [hashtable]$Ui
    )

    $hasCoreFiles = (Test-Path $installedInstallerPath) -or (Test-Path $watchdogScriptPath) -or (Test-Path $installedCliPath)
    $isInstalled = (Test-Path $uninstallPath) -and $hasCoreFiles
    $watchdogState = Get-WatchdogState
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

    return [pscustomobject]@{
        InstalledLabel = $Ui.Installed
        InstalledValue = $installedValue
        InstalledOk = $isInstalled
        WatchdogLabel = $Ui.Watchdog
        WatchdogValue = $watchdogValue
        WatchdogOk = ($watchdogState -match "Ready|Running")
        RawWatchdogState = $watchdogState
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
        [int]$Width = 80
    )

    $safeWidth = [Math]::Max(20, $Width)
    $trimmed = if ($Text.Length -gt $safeWidth) { $Text.Substring(0, $safeWidth) } else { $Text }
    $padded = $trimmed.PadRight($safeWidth)
    Write-Host $padded -ForegroundColor Black -BackgroundColor Cyan
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

function Get-UpdateAvailability {
    param(
        [pscustomobject]$Status,
        [hashtable]$Ui
    )

    if (-not $Status.InstalledOk) {
        return $false
    }

    try {
        $updateCheckPath = Join-Path $tempDir "AutoVencord-update-check.bat"
        New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
        Download-File $installerUrl $updateCheckPath

        if (-not (Test-Path $installedInstallerPath)) {
            return $true
        }

        return (-not (Test-SameFileHash -LeftPath $installedInstallerPath -RightPath $updateCheckPath))
    } catch {
        return $false
    }
}

function Get-MenuEnabledStates {
    param(
        [pscustomobject]$Status
    )

    return @(
        (-not $Status.InstalledOk),
        $Status.InstalledOk,
        $Status.InstalledOk,
        $true
    )
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
    Write-PaddedLine -Text "" -Width $width

    for ($i = 0; $i -lt $Options.Length; $i++) {
        $label = $Options[$i]
        $enabled = $EnabledStates[$i]
        $contentWidth = [Math]::Max(20, $width - 6)
        $content = ("  {0}" -f $label)

        if ($content.Length -gt $contentWidth) {
            $content = $content.Substring(0, $contentWidth)
        }

        $line = $content.PadRight($contentWidth)

        if (-not $enabled) {
            Write-PaddedLine -Text ($line + "   ") -ForegroundColor DarkGray -Width $width
        } elseif ($i -eq $SelectedIndex) {
            Write-SelectedLine -Text ($line + " >>") -Width $width
        } else {
            Write-PaddedLine -Text ($line + "   ") -ForegroundColor Gray -Width $width
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

function Download-LatestInstaller {
    param(
        [hashtable]$Ui
    )

    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
    Write-Host $Ui.Downloading -ForegroundColor Cyan
    Download-File $installerUrl $batPath
    return $batPath
}

function Invoke-InstallerBatch {
    param(
        [string]$InstallerBatchPath
    )

    $oldSkipSelfUpdate = $env:AUTOVENCORD_SKIP_SELF_UPDATE
    $oldNoPause = $env:AUTOVENCORD_NO_PAUSE

    try {
        $env:AUTOVENCORD_SKIP_SELF_UPDATE = "1"
        $env:AUTOVENCORD_NO_PAUSE = "1"
        & $InstallerBatchPath
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
        [string[]]$Options
    )

    $firstRender = $true
    $status = Get-StatusText -Ui $Ui
    $updateAvailable = Get-UpdateAvailability -Status $status -Ui $Ui
    $menuOptions = @($Options[0], $Options[1], $Options[2], $Options[3])

    if ($updateAvailable) {
        $menuOptions[1] = $menuOptions[1] + $Ui.UpdateAvailableSuffix
    }

    $enabledStates = Get-MenuEnabledStates -Status $status
    $index = 0

    for ($i = 0; $i -lt $enabledStates.Length; $i++) {
        if ($enabledStates[$i]) {
            $index = $i
            break
        }
    }

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
    }
}

function Invoke-Install {
    param(
        [hashtable]$Ui
    )

    $downloadedInstallerPath = Download-LatestInstaller -Ui $Ui
    Invoke-InstallerBatch -InstallerBatchPath $downloadedInstallerPath
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

    Write-Host $Ui.Updating -ForegroundColor Cyan
    $downloadedInstallerPath = Download-LatestInstaller -Ui $Ui

    if ((Test-Path $installedInstallerPath) -and (Test-SameFileHash -LeftPath $installedInstallerPath -RightPath $downloadedInstallerPath)) {
        Write-Host $Ui.AlreadyLatest -ForegroundColor Green
        return
    }

    Invoke-InstallerBatch -InstallerBatchPath $downloadedInstallerPath
}

function Open-InstallFolder {
    New-Item -ItemType Directory -Force -Path $installedBaseDir | Out-Null
    Start-Process explorer.exe $installedBaseDir
}

$ui = Get-UiText
$selection = $null
$autoAction = $env:AUTOVENCORD_MENU_ACTION

if ($autoAction) {
    switch ($autoAction.ToLowerInvariant()) {
        "install" { $selection = 0 }
        "update" { $selection = 1 }
        "uninstall" { $selection = 2 }
        "open" { $selection = 3 }
    }
}

if ($null -eq $selection) {
    $selection = Show-Menu -Ui $ui -Options @($ui.Install, $ui.Update, $ui.Uninstall, $ui.OpenFolder)
}

if (-not $autoAction -and $selection -eq 0) {
    if (-not (Confirm-InstallSelection -Ui $ui)) {
        $selection = Show-Menu -Ui $ui -Options @($ui.Install, $ui.Update, $ui.Uninstall, $ui.OpenFolder)
    }
}

Clear-Host

if ($selection -eq 0) {
    Invoke-Install -Ui $ui
} elseif ($selection -eq 1) {
    Invoke-Update -Ui $ui
} elseif ($selection -eq 2) {
    Invoke-Uninstall -Ui $ui
} else {
    Open-InstallFolder
}
