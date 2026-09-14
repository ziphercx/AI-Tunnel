@echo off
setlocal EnableExtensions
chcp 65001 >nul 2>&1
title POOHHUB Tunnel-V4.2 - Remove Not Needed Files
cd /d "%~dp0"

echo ============================================================
echo   POOHHUB Tunnel-V4.2 - REMOVE NOT NEEDED / OLD LOGS
echo ============================================================
echo.
echo This cleanup removes only known disposable files:
echo   - Old startup logs under runtime\start
echo   - Historical runtime logs
echo   - mcp-demo-files\.keep placeholder
echo.
echo [KEEP] node - will NOT be deleted
echo [KEEP] workspace, scripts, config, .env and tunnel-client.exe
echo.

set /a REMOVED=0

if exist "runtime\start\*.log" (
    echo [1/3] Removing old startup logs...
    del /q /f "runtime\start\*.log" >nul 2>&1
    set /a REMOVED+=1
) else echo [1/3] No old startup logs found.

if exist "runtime\logs" (
    echo [2/3] Removing disposable historical runtime logs...
    for %%F in ("runtime\logs\tunnel.stdout.log" "runtime\logs\errors.log" "runtime\logs\activity.log" "runtime\logs\setup.stderr.log" "runtime\logs\last-action-error.log" "runtime\logs\tunnel-host.log" "runtime\logs\setup.log" "runtime\logs\tunnel.stderr.log") do (
        if exist "%%~F" (
            del /q /f "%%~F" >nul 2>&1
            if not exist "%%~F" set /a REMOVED+=1
        )
    )
) else echo [2/3] Runtime logs directory not found.

if exist "mcp-demo-files\.keep" (
    echo [3/3] Removing placeholder mcp-demo-files\.keep...
    del /q /f "mcp-demo-files\.keep" >nul 2>&1
    if not exist "mcp-demo-files\.keep" set /a REMOVED+=1
) else echo [3/3] No placeholder file found.

echo.
echo ============================================================
echo Cleanup finished - removed groups: %REMOVED%
echo ============================================================
echo.
echo Files intentionally kept:
echo   [KEEP] node
echo   [KEEP] workspace
echo   [KEEP] scripts and config
echo   [KEEP] tunnel-client.exe
echo   [KEEP] tunnel\gptwork.yaml and tunnel\.env
echo   [KEEP] runtime approval state
echo.
pause
endlocal
