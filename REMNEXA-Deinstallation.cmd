@echo off
setlocal
title REMNEXA - Deinstallation
set "APP_PWSH=%~dp0runtime\pwsh.exe"
if exist "%APP_PWSH%" goto run_remnexa
where.exe pwsh.exe >nul 2>nul
if errorlevel 1 goto runtime_missing
set "APP_PWSH=pwsh.exe"
:run_remnexa
"%APP_PWSH%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0REMNEXA.ps1" -WorkspaceMode Uninstall
exit /b %errorlevel%
:runtime_missing
echo PowerShell 7.5 oder neuer fehlt. Installiere PowerShell 7.5+ oder fuege pwsh.exe zum PATH hinzu.
pause
exit /b 1
