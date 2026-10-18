<#
 Runs Godot headless with output going to a log file, polls it, and kills Godot straight away on
 "SCRIPT ERROR", "Parse Error" or "Failed to load script" (headless Godot does not quit on a script error), or when no new
 output has appeared for -Seconds. Prints the tail of the log and exits non-zero on a kill or a non-zero Godot exit code.
 Usage:  powershell -File tools/godot_guard.ps1 -Seconds 120 -Args "--headless","--path",".","--script","res://tests/run_one.gd","--","nav_perf_test"
#>
param(
	[int]$Seconds = 120,
	[Alias("Args")][string[]]$GodotArgs = @(),
	[string]$Godot = "C:\Users\lloyd\AppData\Local\Godot47\Godot_v4.7-stable_win64_console.exe",
	[string]$Log = "",
	[int]$Tail = 40
)
$root = Split-Path -Parent $PSScriptRoot
if ($Log -eq "") { $Log = Join-Path $env:TEMP ("godot_guard_" + [guid]::NewGuid().ToString("N").Substring(0, 8) + ".log") }
$err = "$Log.err"
if ($GodotArgs.Count -eq 1) { $GodotArgs = @($GodotArgs[0] -split ",") }   # powershell -File flattens "a","b" into the single string "a,b"
$argLine = ($GodotArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join " "
$p = Start-Process -FilePath $Godot -ArgumentList $argLine -WorkingDirectory $root -RedirectStandardOutput $Log -RedirectStandardError $err -PassThru -NoNewWindow
if ($null -eq $p) { Write-Host "GUARD: could not start Godot"; exit 4 }
$null = $p.Handle          # keeps the exit code readable after the process ends
$bad = "SCRIPT ERROR|Parse Error|Failed to load script"
$lastSize = -1
$lastChange = Get-Date
$reason = ""
while (-not $p.HasExited) {
	Start-Sleep -Milliseconds 500
	$size = (Get-Item $Log -ErrorAction SilentlyContinue).Length + (Get-Item $err -ErrorAction SilentlyContinue).Length
	if ($size -ne $lastSize) { $lastSize = $size; $lastChange = Get-Date }
	$text = (Get-Content $Log -Raw -ErrorAction SilentlyContinue) + (Get-Content $err -Raw -ErrorAction SilentlyContinue)
	if ($text -match $bad) { $reason = "script error in output"; break }
	if (((Get-Date) - $lastChange).TotalSeconds -gt $Seconds) { $reason = "no output for $Seconds s"; break }
}
if ($reason -ne "") { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
else { $p.WaitForExit() }
Start-Sleep -Milliseconds 200
(Get-Content $Log -Tail $Tail -ErrorAction SilentlyContinue)
(Get-Content $err -Tail 10 -ErrorAction SilentlyContinue)
if ($reason -ne "") { Write-Host "GUARD: killed Godot ($reason). Full log: $Log"; exit 3 }
Write-Host "GUARD: Godot exited with code $($p.ExitCode). Full log: $Log"
exit $p.ExitCode
