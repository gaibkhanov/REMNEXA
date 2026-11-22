@echo off
rem Compatibility forwarding; not shipped in the end-user package.
call "%~dp0REMNEXA.cmd" -WorkspaceMode Uninstall %*
exit /b %errorlevel%
