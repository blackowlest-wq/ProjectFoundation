@echo off
setlocal
where pwsh.exe >nul 2>&1
if errorlevel 1 (
    echo PowerShell 7 (pwsh.exe) is required for Oracle tests. 1>&2
    exit /b 1
)
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0test-oracle.ps1" %*
exit /b %ERRORLEVEL%
