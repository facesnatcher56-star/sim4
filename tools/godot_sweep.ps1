<#
 Kills runaway headless Godot runs: any Godot_v4.7* process older than -MinutesOld (default 45) whose command line has
 --headless / --script / --import, is NOT an editor (--editor / -e) and has no live tools/godot_guard.ps1 among its ancestors.
 Kills the whole tree (taskkill /T /F). -DryRun only prints. -NamePattern / -CommandLineMatch are for tests.
 Watcher loop one-liner:  powershell -NoProfile -File tools/godot_sweep.ps1
#>
param(
	[double]$MinutesOld = 45,
	[switch]$DryRun,
	[string]$NamePattern = "Godot_v4.7*",
	[string]$CommandLineMatch = ""      # tests: only consider processes whose command line contains this text
)
$all = @{}
Get-CimInstance Win32_Process | ForEach-Object { $all[[int]$_.ProcessId] = $_ }
function Has-Guard($proc) {
	$pid2 = [int]$proc.ParentProcessId
	for ($i = 0; $i -lt 8 -and $all.ContainsKey($pid2); $i++) {
		$par = $all[$pid2]
		if ($par.CommandLine -match "godot_guard\.ps1") { return $true }
		$pid2 = [int]$par.ParentProcessId
	}
	return $false
}
$killed = 0
foreach ($proc in $all.Values) {
	if ($proc.Name -notlike $NamePattern) { continue }
	$cl = [string]$proc.CommandLine
	if ($cl -notmatch "--headless|--script|--import") { continue }
	if ($cl -match "(^|\s)(--editor|-e)(\s|$)") { continue }
	if ($CommandLineMatch -ne "" -and $cl -notlike "*$CommandLineMatch*") { continue }
	if ($proc.CreationDate -eq $null) { continue }
	$age = ((Get-Date) - $proc.CreationDate).TotalMinutes
	if ($age -lt $MinutesOld) { continue }
	if (Has-Guard $proc) { continue }
	Write-Host ("SWEEP: {0} pid {1} age {2:N1} min: {3}" -f $(if ($DryRun) { "would kill" } else { "killing" }), $proc.ProcessId, $age, $cl)
	if (-not $DryRun) { & taskkill.exe /T /F /PID $proc.ProcessId 2>&1 | Out-Null }
	$killed++
}
Write-Host "SWEEP: $killed runaway Godot process(es) $(if ($DryRun) { 'found' } else { 'killed' })"
exit 0
