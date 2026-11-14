@echo off
rem tubepacer launcher for Command Prompt: runs ytdl-cmd.ps1 (next to this file), which re-reads the command
rem line itself so option values keep their ":" and "-", then runs ytdl.ps1.
rem Uses PowerShell 7 (pwsh) if installed, otherwise Windows PowerShell 5.1.
where pwsh >nul 2>nul
if %errorlevel%==0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0ytdl-cmd.ps1" %*
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ytdl-cmd.ps1" %*
)
exit /b %errorlevel%
