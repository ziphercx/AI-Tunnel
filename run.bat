@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0"
title POOH HUB AI-Tunnel V1.2 - Keyboard Control Center

set "TUI=%CD%\scripts\tui.ps1"
if not exist "%TUI%" (
    echo Missing scripts\tui.ps1
    pause
    exit /b 1
)

set "POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%POWERSHELL%" set "POWERSHELL=powershell.exe"

set "CHECKER=%CD%\scripts\check-tui.ps1"
if exist "%CHECKER%" (
    "%POWERSHELL%" -NoProfile -ExecutionPolicy Bypass -File "%CHECKER%" -Path "%TUI%"
    if errorlevel 1 (
        echo.
        echo TUI was not started because the syntax check failed.
        exit /b 2
    )
)

"%POWERSHELL%" -NoProfile -STA -ExecutionPolicy Bypass -File "%TUI%"
set "RC=%ERRORLEVEL%"
endlocal & exit /b %RC%
