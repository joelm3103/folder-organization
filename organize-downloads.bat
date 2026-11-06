@echo off
REM Launcher for organize-downloads.ps1 - sorts this folder's files into category folders.
REM
REM Put this .bat and the .ps1 in the folder you want sorted, then double-click. The folder they
REM sit in is the folder that gets organised; -Path overrides it.
REM
REM Usage: organize-downloads.bat [-Recurse] [-MaxDepth N] [-WhatIf] [-Force] [-LogFile "path"] [-PreviewFile "path"] [-PruneEmpty] ["path to organise"]
REM   -Recurse / -MaxDepth  also sort files found in subfolders (asks first when run interactively)
REM
REM The window stays open at the end so the result can be read. Pass -Force to skip that pause:
REM unattended runs (Task Scheduler) and any other -Force caller exit immediately.
REM
REM Keep this .bat and organize-downloads.ps1 in the same folder.

title Folder Organization Script
setlocal

set "SCRIPT=%~dp0organize-downloads.ps1"

if not exist "%SCRIPT%" (
    echo ERROR: organize-downloads.ps1 was not found next to this launcher.
    echo Expected: "%SCRIPT%"
    echo Keep organize-downloads.bat and organize-downloads.ps1 in the same folder.
    echo.
    pause
    exit /b 1
)

REM Pause unless -Force is present. The scan walks %* token by token rather than piping through
REM findstr, so a quoted path holding spaces, ampersands or parentheses cannot break the check or
REM be mistaken for a switch.
set "PAUSE_AT_END=yes"
for %%A in (%*) do if /i "%%~A"=="-force" set "PAUSE_AT_END=no"

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "RC=%errorlevel%"

echo.
echo Exit code: %RC%

if /i "%PAUSE_AT_END%"=="yes" pause

endlocal & exit /b %RC%
