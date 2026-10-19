<#
 Runs the scale benchmark (tests/perf_scale.gd) through godot_guard.ps1 and appends a dated section to docs/PERF_SCALE_RESULTS.md.
 Usage:  powershell -File tools/run_scale.ps1                      big generated town (320x272, 63 lots, 200 townies), 3 game days (about 3-4 min)
         powershell -File tools/run_scale.ps1 -Profile today       the game's own town
         powershell -File tools/run_scale.ps1 -Profile big -Days 1 -NoWrite
 Exit code = the guard's (0 pass, 1 a budget ceiling / count limit failed, 3 killed by the guard).
#>
param(
	[string]$Profile = "big",
	[int]$Days = 3,
	[switch]$NoWrite,
	[int]$Seconds = 900
)
$a = @("--headless", "--path", ".", "--script", "res://tests/run_one.gd", "--", "perf_scale", "--profile=$Profile", "--days=$Days")
if ($NoWrite) { $a += "--no-write" }
& "$PSScriptRoot\godot_guard.ps1" -Seconds $Seconds -Tail 90 -GodotArgs $a
exit $LASTEXITCODE
