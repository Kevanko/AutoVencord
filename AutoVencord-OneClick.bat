@echo off
setlocal EnableExtensions

set "AUTOVENCORD_INSTALL_URL=https://raw.githubusercontent.com/Kevanko/AutoVencord/main/install.ps1"
set "AUTOVENCORD_INSTALL_FALLBACK_URL=https://github.com/Kevanko/AutoVencord/raw/main/install.ps1"
set "AUTOVENCORD_TEMP_PS1=%TEMP%\AutoVencord-install-%RANDOM%%RANDOM%.ps1"
set "AUTOVENCORD_PAYLOAD_MARKER=AUTOVENCORD_PAYLOAD_VERSION"

echo Starting AutoVencord menu...

powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference = 'Stop'; try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]3072 } catch {}; $out = $env:AUTOVENCORD_TEMP_PS1; $urls = @($env:AUTOVENCORD_INSTALL_URL, $env:AUTOVENCORD_INSTALL_FALLBACK_URL); $lastError = $null; foreach ($url in $urls) { try { if (Get-Command Invoke-WebRequest -ErrorAction SilentlyContinue) { Invoke-WebRequest -UseBasicParsing $url -OutFile $out } else { (New-Object System.Net.WebClient).DownloadFile($url, $out) }; $content = Get-Content -LiteralPath $out -Raw; if ($content.Contains($env:AUTOVENCORD_PAYLOAD_MARKER) -and $content.Contains('Show-Menu')) { exit 0 }; throw 'Downloaded install.ps1 is stale or invalid.' } catch { $lastError = $_; Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue } }; throw $lastError"
if errorlevel 1 (
    echo.
    echo Failed to download AutoVencord menu.
    call :MaybePause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%AUTOVENCORD_TEMP_PS1%"
set "EXITCODE=%ERRORLEVEL%"
del "%AUTOVENCORD_TEMP_PS1%" >nul 2>&1

if not "%EXITCODE%"=="0" (
    echo.
    echo AutoVencord menu exited with code %EXITCODE%.
    call :MaybePause
    exit /b %EXITCODE%
)

call :MaybePause
exit /b 0

:MaybePause
if not "%AUTOVENCORD_NO_PAUSE%"=="1" pause
exit /b 0
