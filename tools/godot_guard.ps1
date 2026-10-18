<#
 Runs Godot headless with output going to a log file, polls it, and kills Godot straight away on
 "SCRIPT ERROR", "Parse Error" or "Failed to load script" (headless Godot does not quit on a script error), or when no new
 output has appeared for -Seconds. Prints the tail of the log and exits non-zero on a kill or a non-zero Godot exit code.
 Also enforces a TOTAL wall limit (-MaxSeconds; auto: single test 300, run_all 900, --slow 2400, --import 900) so a run that
 keeps printing is killed, runs Godot at below-normal priority, and puts it in a Windows Job Object (kill-on-close) so Godot and
 all its children die even if this guard is killed. The whole process tree is stopped in a finally block. Exit 3 = killed.
 Usage:  powershell -File tools/godot_guard.ps1 -Seconds 120 -Args "--headless","--path",".","--script","res://tests/run_one.gd","--","nav_perf_test"
#>
param(
	[int]$Seconds = 120,
	[Alias("Args")][string[]]$GodotArgs = @(),
	[string]$Godot = "C:\Users\lloyd\AppData\Local\Godot47\Godot_v4.7-stable_win64_console.exe",
	[string]$Log = "",
	[int]$Tail = 40,
	[int]$MaxSeconds = 0     # 0 = choose from the args
)
$root = Split-Path -Parent $PSScriptRoot
if ($Log -eq "") { $Log = Join-Path $env:TEMP ("godot_guard_" + [guid]::NewGuid().ToString("N").Substring(0, 8) + ".log") }
$err = "$Log.err"
if ($GodotArgs.Count -eq 1) { $GodotArgs = @($GodotArgs[0] -split ",") }   # powershell -File flattens "a","b" into the single string "a,b"
if ($MaxSeconds -le 0) {
	$joined = $GodotArgs -join " "
	if ($joined -match "--import") { $MaxSeconds = 900 }
	elseif ($joined -match "--slow|--all") { $MaxSeconds = 2400 }
	elseif ($joined -match "run_all\.gd") { $MaxSeconds = 900 }
	else { $MaxSeconds = 300 }
}
$argLine = ($GodotArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join " "
if (-not ("GuardJob" -as [type])) {
	Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class GuardJob {
	[DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern IntPtr CreateJobObject(IntPtr a, string n);
	[DllImport("kernel32.dll")] static extern bool SetInformationJobObject(IntPtr j, int c, IntPtr i, int l);
	[DllImport("kernel32.dll")] static extern bool AssignProcessToJobObject(IntPtr j, IntPtr p);
	public static IntPtr Make() {   // kill-on-close job, handle intentionally never closed: it closes when this process dies
		IntPtr j = CreateJobObject(IntPtr.Zero, null);
		IntPtr buf = Marshal.AllocHGlobal(144);
		for (int k = 0; k < 144; k++) Marshal.WriteByte(buf, k, 0);
		Marshal.WriteInt32(buf, 16, 0x2000);   // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
		SetInformationJobObject(j, 9, buf, 144);
		return j;
	}
	public static bool Add(IntPtr j, IntPtr p) { return AssignProcessToJobObject(j, p); }
}
"@
}
$job = [GuardJob]::Make()
$p = Start-Process -FilePath $Godot -ArgumentList $argLine -WorkingDirectory $root -RedirectStandardOutput $Log -RedirectStandardError $err -PassThru -NoNewWindow
if ($null -eq $p) { Write-Host "GUARD: could not start Godot"; exit 4 }
$null = $p.Handle          # keeps the exit code readable after the process ends
try { $null = [GuardJob]::Add($job, $p.Handle); $p.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::BelowNormal } catch {}
$bad = "SCRIPT ERROR|Parse Error|Failed to load script|TIMEOUT in "   # TIMEOUT = in-engine watchdog fired (OS.kill exits 0)
$lastSize = -1
$start = Get-Date
$lastChange = $start
$reason = ""
try {
	while (-not $p.HasExited) {
		Start-Sleep -Milliseconds 500
		$size = (Get-Item $Log -ErrorAction SilentlyContinue).Length + (Get-Item $err -ErrorAction SilentlyContinue).Length
		if ($size -ne $lastSize) { $lastSize = $size; $lastChange = Get-Date }
		$text = (Get-Content $Log -Raw -ErrorAction SilentlyContinue) + (Get-Content $err -Raw -ErrorAction SilentlyContinue)
		if ($text -match $bad) { $reason = "script error in output"; break }
		if (((Get-Date) - $lastChange).TotalSeconds -gt $Seconds) { $reason = "no output for $Seconds s"; break }
		if (((Get-Date) - $start).TotalSeconds -gt $MaxSeconds) { $reason = "total time limit $MaxSeconds s exceeded"; break }
	}
	if ($reason -eq "") { $p.WaitForExit() }
}
finally {
	if (-not $p.HasExited -or $reason -ne "") {
		& taskkill.exe /T /F /PID $p.Id 2>&1 | Out-Null     # Godot and every child
		Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
	}
}
Start-Sleep -Milliseconds 200
(Get-Content $Log -Tail $Tail -ErrorAction SilentlyContinue)
(Get-Content $err -Tail 10 -ErrorAction SilentlyContinue)
if ($reason -ne "") { Write-Host "GUARD: killed Godot ($reason). Full log: $Log"; exit 3 }
Write-Host "GUARD: Godot exited with code $($p.ExitCode). Full log: $Log"
exit $p.ExitCode
