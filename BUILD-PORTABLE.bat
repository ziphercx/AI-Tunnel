@echo off
setlocal
cd /d "%~dp0"
title POOH HUB AI-Tunnel V1.2 - Build Portable Package
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\BUILD-PORTABLE.ps1"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
  echo.
  echo Portable package build failed.
  pause
)
endlocal & exit /b %RC%
