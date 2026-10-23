<#
 Runs tools/sweep.gd (hidden, never takes focus) and watches it: the sweep prints a BEAT line every 5 s, so a log that stops growing for -Stall
 seconds is a frozen game. The run is then killed, "HANG" and the last log lines go into the log, and the sweep is restarted after the object kind it
 froze on. A run that floods the same SCRIPT ERROR is killed too. Usage:
   powershell -File tools/sweep_watch.ps1 -Out <dir> [-Phases "self objects"] [-Stall 45]
#>
param([string]$Out, [string]$Phases = "", [int]$Stall = 45, [int]$Skip = 0)
$root = Split-Path -Parent $PSScriptRoot
$g = "C:\Users\lloyd\AppData\Local\Godot47\Godot_v4.7-stable_win64_console.exe"
$ov = Join-Path $root "override.cfg"
New-Item -ItemType Directory -Force $Out | Out-Null
$main = Join-Path $Out "sweep.log"
for ($run = 0; $run -lt 20; $run++) {
	Set-Content -Path $ov -Value "[display]`nwindow/size/no_focus=true`nwindow/size/always_on_top=false`n" -Encoding ascii
	$log = Join-Path $Out ("run$run.log")
	$a = @("--path", $root, "--position", "3440,164", "--resolution", "1920x1080", "--script", "res://tools/sweep.gd", "--", $Out, "skip=$Skip") + ($Phases -split " " | Where-Object { $_ -ne "" })
	$p = Start-Process $g -ArgumentList $a -PassThru -NoNewWindow -RedirectStandardOutput $log -RedirectStandardError "$log.err"
	$last = 0; $quiet = 0; $why = ""
	while (-not $p.HasExited) {
		Start-Sleep -Seconds 5
		$size = (Get-Item $log).Length + (Get-Item "$log.err").Length
		if ($size -eq $last) { $quiet += 5 } else { $quiet = 0; $last = $size }
		if ($quiet -ge $Stall) { $why = "HANG: no output for $Stall s" }
		$errs = (Select-String -Path "$log.err", $log -Pattern "SCRIPT ERROR" -ErrorAction SilentlyContinue | Measure-Object).Count
		if ($errs -gt 3000) { $why = "ERROR FLOOD: $errs script errors" }
		if ($why -ne "") { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; break }
	}
	Remove-Item $ov -ErrorAction SilentlyContinue
	Get-Content $log, "$log.err" | Add-Content $main
	if ($why -eq "") { Add-Content $main "WATCH run $run exited with code $($p.ExitCode)"; break }
	$kind = Select-String -Path $log -Pattern "KIND +(\d+)/" | Select-Object -Last 1
	Add-Content $main "WATCH $why (run $run). Last lines:"
	Get-Content $log -Tail 15 | ForEach-Object { Add-Content $main ("WATCH | " + $_) }
	if ($kind -eq $null) { break }          # froze before the object phase: nothing to skip past
	$Skip = [int]$kind.Matches[0].Groups[1].Value + 1
	$Phases = "objects social"
}
