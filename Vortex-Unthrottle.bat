@echo off
setlocal enabledelayedexpansion
title Vortex Unthrottle

:: ── Check Node.js ──────────────────────────────────
where node >nul 2>&1
if %errorlevel% neq 0 (
    echo Node.js is required. Install from https://nodejs.org
    pause
    exit /b 1
)

:: ── Download latest files ──────────────────────────
set "BASE=https://raw.githubusercontent.com/defthrets/vortex-unthrottle/main"
set "TMPDIR=%TEMP%\vortex-unthrottle"
if not exist "%TMPDIR%" mkdir "%TMPDIR%"

echo Downloading latest patcher and proxy...
powershell -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri '%BASE%/unthrottle.ps1' -OutFile '%TMPDIR%\unthrottle.ps1'" 2>nul
powershell -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri '%BASE%/nexus-fast-proxy.js' -OutFile '%TMPDIR%\nexus-fast-proxy.js'" 2>nul

if not exist "%TMPDIR%\unthrottle.ps1" (
    echo Failed to download patcher. Check internet.
    pause
    exit /b 1
)
if not exist "%TMPDIR%\nexus-fast-proxy.js" (
    echo Failed to download proxy. Check internet.
    pause
    exit /b 1
)

:: ── Close Vortex if running ────────────────────────
tasklist /fi "imagename eq Vortex.exe" 2>nul | find /i "Vortex.exe" >nul
if %errorlevel% equ 0 (
    echo Closing Vortex...
    taskkill /f /im Vortex.exe >nul 2>&1
    timeout /t 2 /nobreak >nul
)

:: ── Patch Vortex ───────────────────────────────────
echo.
echo Patching Vortex download caps...
powershell -ExecutionPolicy Bypass -File "%TMPDIR%\unthrottle.ps1"

:: ── Start proxy ────────────────────────────────────
echo.
echo Starting download proxy on 127.0.0.1:8888...
start "Nexus Fast Proxy" /MIN cmd /c "node %TMPDIR%\nexus-fast-proxy.js 8888 > %TMPDIR%\proxy.log 2>&1"
timeout /t 2 /nobreak >nul

:: Verify proxy is running
powershell -ExecutionPolicy Bypass -Command "try { $r = Invoke-WebRequest -Uri 'http://127.0.0.1:8888' -TimeoutSec 3 -UseBasicParsing; exit 0 } catch { exit 1 }" >nul 2>&1
if %errorlevel% neq 0 (
    echo WARNING: Proxy didn't start. Check %TMPDIR%\proxy.log
    echo Downloads will run at normal speed.
)

:: ── Launch Vortex ──────────────────────────────────
set "VORTEX=C:\Program Files\Black Tree Gaming Ltd\Vortex\Vortex.exe"
if exist "%VORTEX%" (
    echo.
    echo Launching Vortex with proxy...
    start "" "%VORTEX%" --proxy-server=http://127.0.0.1:8888
) else (
    echo Vortex not found at %VORTEX%
)

echo.
echo Done. The proxy closes when you close this window.
echo.
pause
