@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0test-oracle.ps1" %*
exit /b %ERRORLEVEL%
