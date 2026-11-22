@echo off
setlocal
rem Source compatibility entry. End-user packages expose REMNEXA.exe only.
if exist "%~dp0REMNEXA.exe" goto run_exe
set "APP_PWSH=%~dp0runtime\pwsh.exe"
if exist "%APP_PWSH%" goto run_remnexa
where.exe pwsh.exe >nul 2>nul
if errorlevel 1 goto runtime_missing
set "APP_PWSH=pwsh.exe"
:run_remnexa
"%APP_PWSH%" -NoLogo -NoProfile -File "%~dp0REMNEXA.ps1" %*
exit /b %errorlevel%
:run_exe
"%~dp0REMNEXA.exe" %*
exit /b %errorlevel%
:runtime_missing
echo PowerShell 7.5+ fehlt / PowerShell 7.5+ is required.
exit /b 10
