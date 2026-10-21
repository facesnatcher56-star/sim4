@echo off
rem Double-click to play Folk.
set "GODOT=C:\Users\lloyd\AppData\Local\Godot47\Godot_v4.7-stable_win64.exe"
if not exist "%GODOT%" set "GODOT=C:\Users\lloyd\AppData\Local\Godot47\Godot_v4.7-stable_win64_console.exe"
if not exist "%GODOT%" (
  echo Could not find Godot at C:\Users\lloyd\AppData\Local\Godot47
  pause
  exit /b 1
)
start "" "%GODOT%" --path "C:\Users\lloyd\OneDrive\Documents\sim-4"
