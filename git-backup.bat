@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title AI Tunnel - Git Backup
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0git-backup.ps1"
if errorlevel 1 (
  echo.
  echo [ERROR] Git backup failed.
  pause
  exit /b 1
)
echo.
echo [DONE] Git backup finished.
pause
