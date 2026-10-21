# Watch the scripted playtest in a normal window. Works from any folder:
#   powershell -ExecutionPolicy Bypass -File "C:\Users\lloyd\OneDrive\Documents\sim-4\tools\watch_playtest.ps1"
# Finds Godot 4.7 itself (the usual install folder, then anything on PATH, then a search of the user folders).
$root = Split-Path -Parent $PSScriptRoot
$cands = @(
    (Join-Path $root "tools\godot\Godot_v4.7-stable_win64.exe"),          # the copy next to the game (the app's own AppData is not visible to the user's Windows)
    "C:\Users\lloyd\AppData\Local\Godot47\Godot_v4.7-stable_win64_console.exe",
    "C:\Users\lloyd\AppData\Local\Godot47\Godot_v4.7-stable_win64.exe",
    (Join-Path $env:LOCALAPPDATA "Godot47\Godot_v4.7-stable_win64_console.exe")
)
$g = $cands | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $g) {
    $cmd = Get-Command godot* -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { $g = $cmd.Source }
}
if (-not $g) {
    $g = Get-ChildItem -Path "C:\Users", "C:\Program Files", "C:\Program Files (x86)" -Filter "Godot_v4.7*win64*.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $g) {
    Write-Host "Could not find Godot 4.7. Tell the builder where Godot_v4.7-stable_win64.exe is."
    exit 1
}
Write-Host "Using $g"
& $g --path $root --script res://tools/playtest.gd -- --watch
