@echo off
setlocal
cd /d "%~dp0"
title POOH HUB AI-Tunnel V1.2 - Setup
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File ".\scripts\cleanup-v12.ps1"
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File ".\scripts\setup.ps1"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" pause
endlocal & exit /b %RC%
