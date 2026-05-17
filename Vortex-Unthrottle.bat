@echo off
echo Patching Vortex download speed caps...
powershell -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/defthrets/vortex-unthrottle/main/unthrottle.ps1' -OutFile '%TEMP%\unthrottle.ps1'" 2>nul
if %errorlevel% neq 0 (
    echo Could not download the latest patcher. Check your internet connection.
    pause
    exit /b 1
)
powershell -ExecutionPolicy Bypass -File "%TEMP%\unthrottle.ps1"
echo.
echo Close and reopen Vortex for the changes to take effect.
pause
