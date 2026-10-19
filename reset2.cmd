@echo off
rem Double-click this file (or the "Reset ASR session 2" shortcut on the desktop) to remove
rem asr-session-2, clone it again and set it up. reset.cmd next to it does the work.
rem reset.cmd may pull a new version of this file, so the call and the exit share one block: cmd.exe
rem parses it in one go and reads nothing from this file afterwards.
(
  call "%~dp0reset.cmd" -Session 2 %*
  if errorlevel 1 exit /b 1
  exit /b 0
)
