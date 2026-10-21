# Owner rule: a windowed Godot run must never take the keyboard / mouse focus from the user's other apps, and is placed OFF-SCREEN (x=9000,y=5000, outside both monitors) at 1080p so it never covers the user's windows.
# Usage: powershell -File tools/quiet_godot.ps1 <godot args...>     (e.g. --script res://tools/solo_shot.gd -- phone out.png)
# It writes a temporary override.cfg (display/window/size/no_focus = true: the window is created non-activating) and removes it afterwards.
$root = Split-Path -Parent $PSScriptRoot
$g = "C:\Users\lloyd\AppData\Local\Godot47\Godot_v4.7-stable_win64_console.exe"
$ov = Join-Path $root "override.cfg"
Set-Content -Path $ov -Value "[display]`nwindow/size/no_focus=true`nwindow/size/always_on_top=false`n" -Encoding ascii
try {
    & $g --path $root --position 9000,5000 --resolution 1920x1080 @args
} finally {
    Remove-Item $ov -ErrorAction SilentlyContinue
}
