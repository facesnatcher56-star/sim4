<#
 Runs the FAST test tier as N balanced shards side by side (tests/run_all.gd --shard=k/N, one godot_guard.ps1 each) and prints one
 summary: every FAIL line, each shard's "N test files, F failed, T s" line and the wall time. 174 files take about 580 s in one process on
 a quiet machine; 6 shards finish in about 120 s. Exit code 0 = every shard passed, 1 = a failure, 3 = a shard was killed by its guard.
 Usage:  powershell -File tools/run_fast.ps1                 6 shards
         powershell -File tools/run_fast.ps1 -Shards 4
         powershell -File tools/run_fast.ps1 -Extra "--shuffle=5"   extra run_all flags (comma-separated when more than one)
#>
param(
	[int]$Shards = 6,
	[int]$Seconds = 300,
	[string]$Extra = ""
)
$root = Split-Path -Parent $PSScriptRoot
$guard = Join-Path $PSScriptRoot "godot_guard.ps1"
$stamp = [guid]::NewGuid().ToString("N").Substring(0, 6)
$t0 = Get-Date
$procs = @()
$logs = @()
for ($k = 0; $k -lt $Shards; $k++) {
	$log = Join-Path $env:TEMP ("run_fast_" + $stamp + "_" + $k + ".log")
	$logs += $log
	$a = "--headless,--path,.,--script,res://tests/run_all.gd,--,--shard=$k/$Shards"
	if ($Extra -ne "") { $a += "," + $Extra }
	$p = Start-Process -FilePath "powershell" -ArgumentList @("-NoProfile", "-File", $guard, "-Seconds", $Seconds, "-Tail", "0", "-Log", $log, "-Args", $a) `
		-WorkingDirectory $root -PassThru -NoNewWindow -RedirectStandardOutput ($log + ".out") -RedirectStandardError ($log + ".err2")
	$null = $p.Handle
	$procs += $p
}
$procs | Wait-Process
$wall = [int]((Get-Date) - $t0).TotalSeconds
$worst = 0
$files = 0
$failed = 0
for ($k = 0; $k -lt $Shards; $k++) {
	$text = Get-Content $logs[$k] -ErrorAction SilentlyContinue
	$fails = $text | Select-String -Pattern "^FAIL |^      - |TIMEOUT in " | ForEach-Object { $_.Line }
	foreach ($l in $fails) { Write-Host ("shard $k  " + $l) }
	$sum = ($text | Select-String -Pattern "^---- (\d+) test files, (\d+) failed, ([0-9.]+) s" | Select-Object -Last 1)
	if ($null -ne $sum) {
		$files += [int]$sum.Matches[0].Groups[1].Value
		$failed += [int]$sum.Matches[0].Groups[2].Value
		Write-Host ("shard $k  " + $sum.Line.Trim("- "))
	} else {
		Write-Host ("shard $k  no summary (killed or crashed): " + $logs[$k])
		$failed += 1
	}
	$code = $procs[$k].ExitCode
	if ($code -gt $worst) { $worst = $code }
}
Write-Host ("---- fast tier in $Shards shards: $files test files, $failed failed, $wall s wall ----")
if ($failed -gt 0 -and $worst -eq 0) { $worst = 1 }
exit $worst
