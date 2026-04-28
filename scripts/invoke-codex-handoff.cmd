@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0invoke-codex-handoff.ps1" %*
exit /b %ERRORLEVEL%
