$ErrorActionPreference = "Stop"

$repoBaseUrl = "https://raw.githubusercontent.com/Kevanko/AutoVencord/main"
$installerUrl = "$repoBaseUrl/AutoVencord-OneClick.bat"
$dotnetInstallUrl = "https://dot.net/v1/dotnet-install.ps1"
$tempDir = Join-Path $env:TEMP "AutoVencord"
$batPath = Join-Path $tempDir "AutoVencord-OneClick.bat"
$installedBaseDir = Join-Path $env:LOCALAPPDATA "AutoVencord"
$uninstallPath = Join-Path $installedBaseDir "uninstall.bat"
$windowTitle = "AutoVencord"
$taskName = "AutoVencord Watchdog"
$tuiRootDir = Join-Path $installedBaseDir "tui"
$tuiProjectDir = Join-Path $tuiRootDir "src\\AutoVencord.Tui"
$tuiProjectPath = Join-Path $tuiProjectDir "AutoVencord.Tui.csproj"
$tuiProgramPath = Join-Path $tuiProjectDir "Program.cs"
$tuiNuGetConfigPath = Join-Path $tuiRootDir "NuGet.Config"
$tuiResultPath = Join-Path $tuiRootDir "selection.txt"
$localDotNetDir = Join-Path $installedBaseDir ".dotnet"
$localDotNetPath = Join-Path $localDotNetDir "dotnet.exe"

function Enable-Tls12IfAvailable {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]3072
    } catch {}
}

function Download-File($url, $outFile) {
    Enable-Tls12IfAvailable
    New-Item -ItemType Directory -Force -Path ([System.IO.Path]::GetDirectoryName($outFile)) | Out-Null

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

function Get-UiText {
    $language = "en"

    try {
        $language = [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName
    } catch {}

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
            PreparingUi = Join-CodePoints @(1055,1086,1076,1075,1086,1090,1072,1074,1083,1080,1074,1072,1102,32,1085,1086,1074,1099,1081,32,1080,1085,1090,1077,1088,1072,1082,1090,1080,1074,1085,1099,1081,32,1080,1085,1090,1077,1088,1092,1077,1081,1089,46,46,46)
            InstallingSdk = Join-CodePoints @(1059,1089,1090,1072,1085,1072,1074,1083,1080,1074,1072,1102,32,1083,1086,1082,1072,1083,1100,1085,1099,1081,32,46,78,69,84,32,83,68,75,32,1076,1083,1103,32,84,85,73,45,1084,1077,1085,1102,46,46,46)
            BuildingUi = Join-CodePoints @(1057,1086,1073,1080,1088,1072,1102,32,84,85,73,45,1080,1085,1090,1077,1088,1092,1077,1081,1089,46,46,46)
            FallbackMenu = Join-CodePoints @(1053,1086,1074,1099,1081,32,84,85,73,32,1080,1085,1090,1077,1088,1092,1077,1081,1089,32,1085,1077,32,1079,1072,1087,1091,1089,1090,1080,1083,1089,1103,44,32,1087,1077,1088,1077,1093,1086,1078,1091,32,1082,32,1088,1077,1079,1077,1088,1074,1085,1086,1084,1091,32,1084,1077,1085,1102,46)
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
        PreparingUi = "Preparing the new interactive interface..."
        InstallingSdk = "Installing a local .NET SDK for the TUI menu..."
        BuildingUi = "Building the TUI interface..."
        FallbackMenu = "The new TUI could not start. Falling back to the basic menu."
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

    $isInstalled = Test-Path $uninstallPath
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

function Test-DotNetSdk {
    param(
        [string]$DotNetPath
    )

    if (-not (Test-Path $DotNetPath)) {
        return $false
    }

    try {
        $sdks = & $DotNetPath --list-sdks 2>$null
        return [bool]($sdks | Where-Object { $_ -match '^8\.' })
    } catch {
        return $false
    }
}

function Get-DotNetCommand {
    $globalDotNet = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($globalDotNet -and (Test-DotNetSdk -DotNetPath $globalDotNet.Source)) {
        return $globalDotNet.Source
    }

    $candidatePaths = @()

    if ($env:ProgramFiles) {
        $candidatePaths += (Join-Path $env:ProgramFiles "dotnet\\dotnet.exe")
    }

    $programFilesX86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
    if ($programFilesX86) {
        $candidatePaths += (Join-Path $programFilesX86 "dotnet\\dotnet.exe")
    }

    foreach ($candidatePath in $candidatePaths) {
        if (Test-DotNetSdk -DotNetPath $candidatePath) {
            return $candidatePath
        }
    }

    if (Test-DotNetSdk -DotNetPath $localDotNetPath) {
        return $localDotNetPath
    }

    return $null
}

function Ensure-LocalDotNetSdk {
    param(
        [hashtable]$Ui
    )

    $existing = Get-DotNetCommand
    if ($existing) {
        return $existing
    }

    Write-Host $Ui.InstallingSdk -ForegroundColor Cyan

    $installScriptPath = Join-Path $tempDir "dotnet-install.ps1"
    Download-File $dotnetInstallUrl $installScriptPath
    New-Item -ItemType Directory -Force -Path $localDotNetDir | Out-Null

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installScriptPath -Channel 8.0 -Quality GA -InstallDir $localDotNetDir

    if (-not (Test-DotNetSdk -DotNetPath $localDotNetPath)) {
        throw ".NET SDK installation failed."
    }

    return $localDotNetPath
}

function Ensure-TuiProjectFiles {
    New-Item -ItemType Directory -Force -Path $tuiProjectDir | Out-Null

    Download-File "$repoBaseUrl/NuGet.Config" $tuiNuGetConfigPath
    Download-File "$repoBaseUrl/src/AutoVencord.Tui/AutoVencord.Tui.csproj" $tuiProjectPath
    Download-File "$repoBaseUrl/src/AutoVencord.Tui/Program.cs" $tuiProgramPath
}

function Invoke-TuiMenu {
    param(
        [hashtable]$Ui,
        [pscustomobject]$Status
    )

    Write-Host $Ui.PreparingUi -ForegroundColor Cyan

    try {
        $dotNetPath = Ensure-LocalDotNetSdk -Ui $Ui
        Ensure-TuiProjectFiles

        Write-Host $Ui.BuildingUi -ForegroundColor Cyan
        & $dotNetPath build $tuiProjectPath -nologo -clp:ErrorsOnly --configfile $tuiNuGetConfigPath | Out-Null
        if ($LASTEXITCODE -ne 0) {
            return $null
        }

        $dllPath = Join-Path $tuiProjectDir "bin\\Debug\\net8.0\\AutoVencord.Tui.dll"
        if (-not (Test-Path $dllPath)) {
            return $null
        }

        if (Test-Path $tuiResultPath) {
            Remove-Item $tuiResultPath -Force -ErrorAction SilentlyContinue
        }

        $tuiArguments = @(
            $dllPath
            "--lang"
            $Ui.Language
            "--installed"
            $Status.InstalledOk.ToString().ToLowerInvariant()
            "--watchdog"
            $Status.RawWatchdogState
            "--result-file"
            $tuiResultPath
        )

        if ($env:AUTOVENCORD_TUI_TEST_ACTION) {
            $tuiArguments += @("--auto-action", $env:AUTOVENCORD_TUI_TEST_ACTION)
        }

        & $dotNetPath @tuiArguments

        if (Test-Path $tuiResultPath) {
            $action = (Get-Content $tuiResultPath -ErrorAction SilentlyContinue | Select-Object -Last 1).Trim()
            if ($action) {
                return $action
            }
        }
    } catch {
        return $null
    }

    return $null
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

function Render-BasicMenu {
    param(
        [hashtable]$Ui,
        [pscustomobject]$Status,
        [string[]]$Options,
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
        $contentWidth = [Math]::Max(20, $width - 6)
        $content = ("  {0}" -f $label)

        if ($content.Length -gt $contentWidth) {
            $content = $content.Substring(0, $contentWidth)
        }

        $line = $content.PadRight($contentWidth)

        if ($i -eq $SelectedIndex) {
            Write-SelectedLine -Text ($line + " >>") -Width $width
        } else {
            Write-PaddedLine -Text ($line + "   ") -ForegroundColor Gray -Width $width
        }
    }

    Write-PaddedLine -Text "" -Width $width
}

function Show-BasicMenu {
    param(
        [hashtable]$Ui,
        [pscustomobject]$Status,
        [string[]]$Options
    )

    $index = 0
    $firstRender = $true

    try {
        $Host.UI.RawUI.WindowTitle = $windowTitle
    } catch {}

    while ($true) {
        Render-BasicMenu -Ui $Ui -Status $Status -Options $Options -SelectedIndex $index -FirstRender $firstRender
        $firstRender = $false

        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

        if ($key.VirtualKeyCode -eq 38) {
            if ($index -gt 0) {
                $index--
            }

            continue
        }

        if ($key.VirtualKeyCode -eq 40) {
            if ($index -lt ($Options.Length - 1)) {
                $index++
            }

            continue
        }

        if ($key.VirtualKeyCode -eq 13) {
            return @("install", "update", "uninstall", "open")[$index]
        }
    }
}

function Resolve-MenuAction {
    param(
        [hashtable]$Ui,
        [pscustomobject]$Status
    )

    $autoAction = $env:AUTOVENCORD_MENU_ACTION
    if ($autoAction) {
        return $autoAction.ToLowerInvariant()
    }

    $action = Invoke-TuiMenu -Ui $Ui -Status $Status
    if ($action) {
        return $action
    }

    Write-Host $Ui.FallbackMenu -ForegroundColor Yellow
    return Show-BasicMenu -Ui $Ui -Status $Status -Options @($Ui.Install, $Ui.Update, $Ui.Uninstall, $Ui.OpenFolder)
}

function Invoke-Install {
    param(
        [hashtable]$Ui
    )

    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
    Write-Host $Ui.Downloading -ForegroundColor Cyan
    Download-File $installerUrl $batPath

    $oldSkipSelfUpdate = $env:AUTOVENCORD_SKIP_SELF_UPDATE
    $oldNoPause = $env:AUTOVENCORD_NO_PAUSE

    try {
        $env:AUTOVENCORD_SKIP_SELF_UPDATE = "1"
        $env:AUTOVENCORD_NO_PAUSE = "1"
        & $batPath
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0) {
            throw "AutoVencord installer failed with exit code $exitCode"
        }
    } finally {
        $env:AUTOVENCORD_SKIP_SELF_UPDATE = $oldSkipSelfUpdate
        $env:AUTOVENCORD_NO_PAUSE = $oldNoPause
    }
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
    & $uninstallPath
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        throw "AutoVencord uninstaller failed with exit code $exitCode"
    }
}

function Invoke-Update {
    param(
        [hashtable]$Ui
    )

    Write-Host $Ui.Updating -ForegroundColor Cyan
    Invoke-Install -Ui $Ui
}

function Open-InstallFolder {
    New-Item -ItemType Directory -Force -Path $installedBaseDir | Out-Null
    Start-Process explorer.exe $installedBaseDir
}

$ui = Get-UiText
$status = Get-StatusText -Ui $ui
$selection = Resolve-MenuAction -Ui $ui -Status $status

Clear-Host

switch ($selection) {
    "install" { Invoke-Install -Ui $ui }
    "update" { Invoke-Update -Ui $ui }
    "uninstall" { Invoke-Uninstall -Ui $ui }
    "open" { Open-InstallFolder }
    default { Open-InstallFolder }
}
