<#
 "It runs" check of one-character play (not a test suite): import, then a real new solo game through the real start code, one in-game day, a scripted
 housing run (move, move back, give up the flat) and a scripted Kiln Quarter run (crew offer, drive-by). Prints one line per check and the first
 script error if there is one. About 2 minutes.   Usage: powershell -File tools/solo_check.ps1
#>
$root = Split-Path -Parent $PSScriptRoot
$guard = Join-Path $PSScriptRoot "godot_guard.ps1"
Set-Location $root
function Run($label, $argline) {
	$out = & powershell -File $guard -Seconds 300 -MaxSeconds 900 -Tail 400 -Args $argline 2>&1 | Out-String
	$bad = ($out -split "`n" | Where-Object { $_ -match "SCRIPT ERROR|Parse Error|Failed to load|GUARD: killed" } | Select-Object -First 3) -join " | "
	$end = ($out -split "`n" | Where-Object { $_ -match "SMOKE end" } | Select-Object -Last 1)
	if ($bad -ne "") { Write-Output "FAIL $label : $bad" } else { Write-Output "ok   $label : $end" }
}
Run "import" "--headless,--path,.,--import"
Run "new game + 1 day" "--headless,--path,.,--script,res://tools/solo_smoke.gd,--,1"
Run "housing run" "--headless,--path,.,--script,res://tools/solo_smoke.gd,--,1,--ladder"
Run "rough district run" "--headless,--path,.,--script,res://tools/solo_smoke.gd,--,1,--rough"
Run "main scene boots" "--headless,--path,.,--quit-after,1500,--,--autostart"
Write-Output (& powershell -File (Join-Path $PSScriptRoot "heritage_guard.ps1") | Out-String)
$g = "C:\Users\lloyd\AppData\Local\Godot47\Godot_v4.7-stable_win64_console.exe"
$p = Start-Process $g -ArgumentList "--path",".","--position","3440,164","--resolution","1920x1080","--quit-after","300" -PassThru -Wait -NoNewWindow -WorkingDirectory $root
if ($p.ExitCode -eq 0) { Write-Output "ok   windowed title screen quits clean" } else { Write-Output "FAIL windowed title screen exit code $($p.ExitCode)" }
