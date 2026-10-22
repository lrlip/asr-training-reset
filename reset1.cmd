@echo off
rem Double-click this file (or the "Reset ASR session 1" shortcut on the desktop) to remove
rem asr-session-1, clone it again and set it up, without asking first. reset.cmd does the work.
rem reset.cmd may pull a new version of this file, so the call and the exit share one block: cmd.exe
rem parses it in one go and reads nothing from this file afterwards.
(
  call "%~dp0reset.cmd" -Session 1 -Force %*
  if errorlevel 1 exit /b 1
  exit /b 0
)
