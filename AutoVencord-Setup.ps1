param(
    [string]$SourceBatPath,
    [string]$SourceSetupPath,
    [string]$SourceCorePath,
    [string]$SourcePayloadManifestPath,
    [switch]$PatchNow
)

$ErrorActionPreference = "Stop"

$payloadVersion = "2026.05.15.6"
$payloadRef = if ($env:AUTOVENCORD_PAYLOAD_REF) { $env:AUTOVENCORD_PAYLOAD_REF } else { "main" }
$baseDir = Join-Path $env:LOCALAPPDATA "AutoVencord"
$taskName = "AutoVencord Watchdog"
$downloadUrl = "https://github.com/Vencord/Installer/releases/latest/download/VencordInstallerCli.exe"
$scriptRoot = if ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PWD.Path }
$tempDir = Join-Path $env:TEMP "AutoVencord"
$bootstrapCorePath = Join-Path $tempDir "AutoVencord.Core.ps1"

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

function Test-CorePayload {
    param(
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    try {
        $content = Get-Content -LiteralPath $Path -Raw
        return ($content.Contains("Get-AutoVencordPayloadVersion") -and $content.Contains($payloadVersion))
    } catch {
        return $false
    }
}

function Get-PayloadCandidateUrls {
    param(
        [string]$FileName
    )

    return @(
        "https://raw.githubusercontent.com/Kevanko/AutoVencord/$payloadRef/${FileName}",
        "https://raw.githubusercontent.com/Kevanko/AutoVencord/main/${FileName}",
        "https://github.com/Kevanko/AutoVencord/raw/main/${FileName}",
        "https://github.com/Kevanko/AutoVencord/raw/main/${FileName}?raw=1"
    )
}

function Initialize-CoreModule {
    $candidateRoots = @($scriptRoot)
    if ($SourceSetupPath) { $candidateRoots += (Split-Path -Parent $SourceSetupPath) }
    if ($SourceCorePath) { $candidateRoots += (Split-Path -Parent $SourceCorePath) }
    if ($SourcePayloadManifestPath) { $candidateRoots += (Split-Path -Parent $SourcePayloadManifestPath) }
    if ($SourceBatPath) { $candidateRoots += (Split-Path -Parent $SourceBatPath) }
    $candidateRoots = $candidateRoots | Where-Object { $_ } | Select-Object -Unique

    $localCoreCandidates = @(
        foreach ($root in $candidateRoots) {
            Join-Path $root "AutoVencord.Core.ps1"
        }
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique

    foreach ($candidate in $localCoreCandidates) {
        return $candidate
    }

    $null = Invoke-BootstrapDownload -Urls (Get-PayloadCandidateUrls -FileName "AutoVencord.Core.ps1") -DestinationPath $bootstrapCorePath -ValidationScript ${function:Test-CorePayload}
    return $bootstrapCorePath
}

$resolvedCorePath = Initialize-CoreModule
. $resolvedCorePath
Set-AutoVencordContext -BaseDir $baseDir -TaskName $taskName | Out-Null
$exitCodes = Get-AutoVencordExitCodes

function Get-LocalPayloadFile {
    param(
        [string]$FileName
    )

    $candidates = @()

    if ($FileName -eq "AutoVencord-OneClick.bat" -and $SourceBatPath) {
        $candidates += $SourceBatPath
    }

    if ($FileName -eq "AutoVencord-Setup.ps1" -and $SourceSetupPath) {
        $candidates += $SourceSetupPath
    }

    if ($FileName -eq "AutoVencord.Core.ps1" -and $SourceCorePath) {
        $candidates += $SourceCorePath
    }

    if ($FileName -eq "AutoVencord-Payload.json" -and $SourcePayloadManifestPath) {
        $candidates += $SourcePayloadManifestPath
    }

    $candidateRoots = @($scriptRoot)
    if ($SourceSetupPath) { $candidateRoots += (Split-Path -Parent $SourceSetupPath) }
    if ($SourceCorePath) { $candidateRoots += (Split-Path -Parent $SourceCorePath) }
    if ($SourcePayloadManifestPath) { $candidateRoots += (Split-Path -Parent $SourcePayloadManifestPath) }
    if ($SourceBatPath) { $candidateRoots += (Split-Path -Parent $SourceBatPath) }
    $candidateRoots = $candidateRoots | Where-Object { $_ } | Select-Object -Unique

    foreach ($root in $candidateRoots) {
        $candidates += (Join-Path $root $FileName)
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    return $null
}

function Get-PayloadDefinition {
    $localManifest = Get-LocalPayloadFile -FileName "AutoVencord-Payload.json"
    if ($localManifest) {
        return (Read-JsonFile -Path $localManifest)
    }

    $tempManifest = Join-Path $tempDir "AutoVencord-Payload.json"
    $download = Invoke-DownloadToFile -Urls (Get-PayloadCandidateUrls -FileName "AutoVencord-Payload.json") -DestinationPath $tempManifest -MinBytes 32
    if (-not $download.Success) {
        throw "Failed to load payload manifest: $($download.Errors -join '; ')"
    }

    $manifest = Read-JsonFile -Path $tempManifest
    if (-not $manifest) {
        throw "Downloaded payload manifest is invalid."
    }

    return $manifest
}

function Resolve-PayloadFile {
    param(
        [string]$FileName,
        [string]$DestinationPath,
        $PayloadDefinition
    )

    $localSource = Get-LocalPayloadFile -FileName $FileName
    if ($localSource) {
        $tempCopy = "{0}.{1}.tmp" -f $DestinationPath, ([guid]::NewGuid().ToString("N"))
        Copy-Item -LiteralPath $localSource -Destination $tempCopy -Force
        Move-Item -LiteralPath $tempCopy -Destination $DestinationPath -Force
        return
    }

    $hashTable = @{}
    if ($PayloadDefinition.files) {
        foreach ($property in $PayloadDefinition.files.PSObject.Properties) {
            $hashTable[$property.Name] = $property.Value
        }
    }

    $expectedHash = $null
    if ($hashTable.ContainsKey($FileName)) {
        $expectedHash = [string]$hashTable[$FileName]
    }

    $validation = {
        param($Path)
        if (-not $expectedHash) {
            return $true
        }

        $actualHash = Get-FileSha256 -Path $Path
        return ($actualHash -eq $expectedHash)
    }.GetNewClosure()

    $download = Invoke-DownloadToFile -Urls (Get-PayloadCandidateUrls -FileName $FileName) -DestinationPath $DestinationPath -MinBytes 16 -ValidationScript $validation
    if (-not $download.Success) {
        throw "Failed to fetch ${FileName}: $($download.Errors -join '; ')"
    }
}

function Write-UninstallScript {
    $context = Get-AutoVencordContext
    $content = @"
@echo off
setlocal
set "TASK_NAME=$($context.TaskName)"
set "BASE_DIR=%~dp0"
set "SELF=%~f0"
set "CLEANUP=%TEMP%\AutoVencord-cleanup-%RANDOM%%RANDOM%.cmd"
echo Running AutoVencord uninstall...
schtasks /End /TN "%TASK_NAME%" >nul 2>&1
schtasks /Delete /TN "%TASK_NAME%" /F >nul 2>&1
del /f /q "%BASE_DIR%watchdog.ps1" >nul 2>&1
del /f /q "%BASE_DIR%AutoVencord.Core.ps1" >nul 2>&1
del /f /q "%BASE_DIR%VencordInstallerCli.exe" >nul 2>&1
del /f /q "%BASE_DIR%AutoVencord-OneClick.bat" >nul 2>&1
del /f /q "%BASE_DIR%AutoVencord-Setup.ps1" >nul 2>&1
del /f /q "%BASE_DIR%AutoVencord-Setup.sha256" >nul 2>&1
del /f /q "%BASE_DIR%installed-manifest.json" >nul 2>&1
del /f /q "%BASE_DIR%uninstall.bat" >nul 2>&1
del /f /q "%BASE_DIR%last-action.log" >nul 2>&1
del /f /q "%BASE_DIR%last-action.previous.log" >nul 2>&1
> "%CLEANUP%" echo @echo off
>> "%CLEANUP%" echo ping 127.0.0.1 -n 3 ^>nul
>> "%CLEANUP%" echo del /f /q "%SELF%" ^>nul 2^>^&1
>> "%CLEANUP%" echo rmdir "%BASE_DIR%" ^>nul 2^>^&1
>> "%CLEANUP%" echo del /f /q "%%~f0" ^>nul 2^>^&1
start "" /min cmd /c "%CLEANUP%"
if /I not "%AUTOVENCORD_NO_PAUSE%"=="1" pause >nul
"@

    Invoke-AtomicTextWrite -Path $context.UninstallPath -Content $content -Encoding ([System.Text.Encoding]::ASCII)
}

function Install-RuntimePayload {
    param(
        $PayloadDefinition
    )

    $context = Get-AutoVencordContext
    New-Item -ItemType Directory -Force -Path $context.BaseDir | Out-Null

    $fileMap = [ordered]@{
        "AutoVencord.Core.ps1" = $context.CorePath
        "AutoVencord-Setup.ps1" = $context.SetupPath
        "AutoVencord-OneClick.bat" = $context.BatchPath
        "watchdog.ps1" = $context.WatchdogPath
    }

    foreach ($entry in $fileMap.GetEnumerator()) {
        Resolve-PayloadFile -FileName $entry.Key -DestinationPath $entry.Value -PayloadDefinition $PayloadDefinition
        Write-AutoVencordLog -Phase "SETUP" -Action "write-file" -Message ("Prepared {0}" -f $entry.Key)
    }

    Write-UninstallScript
}

function Get-InstalledFileHashes {
    $context = Get-AutoVencordContext
    return [ordered]@{
        "AutoVencord.Core.ps1" = Get-FileSha256 -Path $context.CorePath
        "AutoVencord-Setup.ps1" = Get-FileSha256 -Path $context.SetupPath
        "AutoVencord-OneClick.bat" = Get-FileSha256 -Path $context.BatchPath
        "watchdog.ps1" = Get-FileSha256 -Path $context.WatchdogPath
    }
}

try {
    $preflightState = $null
    if ($PatchNow) {
        $preflightState = Get-DiscordState
        switch ($preflightState.State) {
            "DiscordMissing" {
                Write-Host "Discord was not found. Install Discord before installing AutoVencord." -ForegroundColor Red
                exit $exitCodes.DiscordMissing
            }
            "DiscordIncomplete" {
                Write-Host "Discord looks incomplete. Start Discord once, then try again." -ForegroundColor Red
                exit $exitCodes.DiscordNotReady
            }
        }
    }

    $payloadDefinition = Get-PayloadDefinition
    New-Item -ItemType Directory -Force -Path $baseDir | Out-Null
    Write-AutoVencordLog -Phase "SETUP" -Action "start" -Message "Setup started."

    Stop-AutoVencordTask
    Remove-Item -LiteralPath (Join-Path $baseDir "AutoVencord-Setup.sha256") -Force -ErrorAction SilentlyContinue
    Install-RuntimePayload -PayloadDefinition $payloadDefinition

    $cliDownload = Invoke-DownloadToFile -Urls @($downloadUrl) -DestinationPath (Get-AutoVencordContext).InstallerPath -MinBytes 102400 -ValidationScript ${function:Test-WindowsExecutable}
    if (-not $cliDownload.Success) {
        Write-AutoVencordLog -Phase "SETUP" -Action "cli-download" -Message ($cliDownload.Errors -join "; ")
        exit $exitCodes.CliDownloadFailed
    }

    $fileHashes = Get-InstalledFileHashes
    Write-InstalledPayloadManifest -PayloadVersion $payloadVersion -PayloadRef $payloadRef -FileHashes $fileHashes
    Write-AutoVencordLog -Phase "SETUP" -Action "manifest" -Message "Installed manifest written."

    $patchExitCode = $exitCodes.Success
    if ($PatchNow) {
        Get-Process Discord -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        $readyState = Wait-ForDiscordReady -MaxWaitSeconds 300 -LogPhase "SETUP"

        if ($readyState.State -eq "DiscordReady") {
            Write-Host "Patching Discord with official Vencord CLI..."
            Write-AutoVencordLog -Phase "SETUP" -Action "patch-start" -Message "Initial patch started." -Fingerprint $readyState.Fingerprint
            $patchResult = Invoke-VencordCliAction -InstallerPath (Get-AutoVencordContext).InstallerPath -Action "install" -DiscordRoot (Get-AutoVencordContext).DiscordRoot -TimeoutSeconds 180 -LogPhase "SETUP"
            if (-not $patchResult.Success) {
                Write-Warning "Initial patch failed. Watchdog will retry when Discord is ready."
                Write-AutoVencordLog -Phase "SETUP" -Action "patch-failed" -Message "Initial patch failed." -Fingerprint $readyState.Fingerprint -ExitCode $patchResult.ExitCode
                $patchExitCode = $exitCodes.PatchFailed
            } else {
                $verifiedPatch = Get-PatchState -AppDir (Get-DiscordState).Latest
                if ($verifiedPatch.State -eq "PatchPresent") {
                    Write-AutoVencordLog -Phase "SETUP" -Action "patch-verified" -Message "Initial patch verified." -Fingerprint $verifiedPatch.Fingerprint
                } else {
                    Write-Warning "Initial patch completed, but verification is inconclusive. Watchdog will keep monitoring."
                    Write-AutoVencordLog -Phase "SETUP" -Action "patch-verify" -Message $verifiedPatch.Reason -Fingerprint $verifiedPatch.Fingerprint
                }
            }
        } else {
            Write-Warning "Discord looks busy or incomplete. Watchdog will patch it automatically when it is ready."
            Write-AutoVencordLog -Phase "SETUP" -Action "patch-postpone" -Message $readyState.Message -Fingerprint $readyState.Fingerprint
            $patchExitCode = $exitCodes.DiscordNotReady
        }

        if (-not (Install-AutoVencordTask -ScriptPath (Get-AutoVencordContext).WatchdogPath)) {
            exit $exitCodes.TaskFailed
        }

        Write-AutoVencordLog -Phase "SETUP" -Action "task-installed" -Message "Watchdog task installed."
    } else {
        Write-Host "Patch and watchdog start skipped. Use the installer menu Install or Update action to apply AutoVencord." -ForegroundColor Yellow
        Write-AutoVencordLog -Phase "SETUP" -Action "skip-patch" -Message "Patch and task start skipped because PatchNow was not requested."
    }

    Write-Host ""
    Write-Host "AutoVencord installed successfully." -ForegroundColor Green
    Write-Host "Folder: $baseDir"
    Write-Host "Task:   $taskName"
    Write-Host ""

    exit $patchExitCode
} catch {
    Write-AutoVencordLog -Phase "SETUP" -Action "fatal" -Message $_.Exception.Message
    Write-Error $_.Exception.Message
    exit $exitCodes.NetworkFailure
}
