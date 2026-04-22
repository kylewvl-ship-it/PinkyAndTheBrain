@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0invoke-claude-handoff.ps1" %*
exit /b %ERRORLEVEL%
