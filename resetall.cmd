@echo off
rem Double-click this file (or the "Reset ASR all sessions" shortcut on the desktop) to remove
rem every training session, clone them again and set them up. reset.cmd next to it does the work.
rem reset.cmd may pull a new version of this file, so the call and the exit share one block: cmd.exe
rem parses it in one go and reads nothing from this file afterwards.
(
  call "%~dp0reset.cmd" -Session all %*
  if errorlevel 1 exit /b 1
  exit /b 0
)
