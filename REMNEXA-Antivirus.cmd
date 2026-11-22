@echo off
rem Compatibility forwarding; not shipped in the end-user package.
call "%~dp0REMNEXA.cmd" -WorkspaceMode Antivirus %*
exit /b %errorlevel%
