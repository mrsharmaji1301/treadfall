@echo off
rem TREADFALL self-check. Finds Godot by itself, runs every game mode on
rem this PC and writes the results to _preview\smoke_log.txt and pictures
rem to _preview\shots. This file writes nothing outside the project folder.
setlocal
cd /d "%~dp0"
if not exist "_preview" mkdir "_preview"
set "GODOT=%~1"
if not defined GODOT for /f "usebackq delims=" %%G in (`powershell -NoProfile -ExecutionPolicy Bypass -File "tools\find_godot.ps1"`) do set "GODOT=%%G"
if not defined GODOT (
  echo Godot was not found and no file was picked.
  echo RUN FAILED: Godot exe not found> "_preview\smoke_log.txt"
  pause
  exit /b 1
)
echo Using %GODOT%
echo RUN %DATE% %TIME% with %GODOT%> "_preview\smoke_log.txt"
for %%M in ("river 20" "river2 20" "deep 15" "oasis 20" "coop 150" "settings 4") do (
  echo --- %%~M>> "_preview\smoke_log.txt"
  echo Running %%~M ...
  "%GODOT%" --path . res://tools/smoke.tscn -- %%~M
)
echo --- river 10 windowed>> "_preview\smoke_log.txt"
"%GODOT%" --path . res://tools/smoke.tscn -- river 10 windowed
echo ALL CHECKS FINISHED>> "_preview\smoke_log.txt"
echo.
echo All checks finished. You can close this window.
pause
