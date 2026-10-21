@echo off
rem Double-click to play Folk. Godot 4.7 sits next to the game in tools\godot (not in git).
set "GAME=C:\Users\lloyd\OneDrive\Documents\sim-4"
set "GODOT=%GAME%\tools\godot\Godot_v4.7-stable_win64.exe"
if not exist "%GODOT%" set "GODOT=C:\Users\lloyd\AppData\Roaming\Godot_v4.7-stable_win64.exe"
if not exist "%GODOT%" (
  echo Could not find Godot 4.7 in %GAME%\tools\godot
  pause
  exit /b 1
)
start "" "%GODOT%" --path "%GAME%"
