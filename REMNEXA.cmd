@echo off
setlocal
title REMNEXA
set "APP_PWSH=%~dp0runtime\pwsh.exe"

if exist "%APP_PWSH%" goto run_remnexa
where.exe pwsh.exe >nul 2>nul
if errorlevel 1 goto runtime_missing
set "APP_PWSH=pwsh.exe"

:run_remnexa

"%APP_PWSH%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0REMNEXA.ps1" -WorkspaceMode Home
exit /b %errorlevel%

:runtime_missing
echo PowerShell 7.5 oder neuer fehlt. Bitte portable Laufzeit mitliefern
echo oder PowerShell 7.5+ installieren und pwsh.exe zum PATH hinzufuegen.
echo.
echo Bitte den kompletten REMNEXA-Ordner kopieren, einschliesslich runtime.

:wait_for_exit
set "APP_COMMAND="
set /p "APP_COMMAND=Zum Beenden exit eingeben: "
if /i not "%APP_COMMAND%"=="exit" goto wait_for_exit
exit /b 1
