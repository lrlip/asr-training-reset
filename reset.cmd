@echo off
rem Double-click this file to choose which training sessions to remove, clone again and set up;
rem reset1.cmd, reset2.cmd and resetall.cmd skip the choice. It first pulls the latest version of
rem this launcher, then runs reset.ps1 next to it with the execution policy bypassed for this run
rem only and keeps the window open so the messages stay readable.
setlocal
set "RESET_DIRECTORY=%~dp0"
set "RESET_SCRIPT=%~dp0reset.ps1"
rem The launcher repository is public, so a pull must never wait for a password.
set "GIT_TERMINAL_PROMPT=0"

rem cmd.exe reads a batch file line by line while it runs, so a pull that changes this file would
rem make it read the rest from the new version at the old position. A block in parentheses is
rem parsed in one go, so everything from the pull on lives in this one block. Inside it a %VARIABLE%
rem is filled in when the block is parsed, so exit codes are checked with "if errorlevel". The texts
rem inside the block have no parentheses: those would end the block.
(
  rem Explorer runs a .cmd straight from a zip in a temporary folder, without the files next to it.
  if not exist "%RESET_SCRIPT%" (
    echo reset.ps1 is not next to this file. If you opened the zip, extract it first:
    echo right-click the zip, choose Extract All, and double-click reset.cmd in the extracted folder.
    echo Press any key to close this window.
    pause >nul
    exit /b 1
  )

  rem A launcher from a zip has no .git and cannot update itself.
  if exist "%RESET_DIRECTORY%.git" (
    echo Updating the reset buttons...
    git -C "%RESET_DIRECTORY%." pull --ff-only
    if errorlevel 1 echo Could not update the reset buttons. Resetting with the version on this laptop.
  )

  rem Files from a downloaded zip carry the Mark of the Web, which a RemoteSigned policy refuses to run.
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath $env:RESET_DIRECTORY -File -Filter *.ps1 -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue" >nul 2>&1

  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%RESET_SCRIPT%" %*
  if errorlevel 1 (
    echo.
    echo Reset did not finish. Read the messages above.
    echo Press any key to close this window.
    pause >nul
    exit /b 1
  )
  echo.
  echo Reset finished. Press any key to close this window.
  pause >nul
  exit /b 0
)
