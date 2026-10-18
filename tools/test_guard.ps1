<# Self-test for godot_guard.ps1 / godot_sweep.ps1 and the in-engine watchdog (about 1 minute). Exit 0 = all pass.
   powershell -NoProfile -File tools/test_guard.ps1 #>
$root = Split-Path -Parent $PSScriptRoot
$godot = "C:\Users\lloyd\AppData\Local\Godot47\Godot_v4.7-stable_win64_console.exe"
$guard = Join-Path $PSScriptRoot "godot_guard.ps1"
$sweep = Join-Path $PSScriptRoot "godot_sweep.ps1"
$fails = 0
function Check($name, $ok) { if ($ok) { Write-Host "PASS  $name" } else { Write-Host "FAIL  $name"; $script:fails++ } }
function Find-Godot($marker) { @(Get-CimInstance Win32_Process | Where-Object { $_.Name -like "Godot_v4.7*" -and $_.CommandLine -like "*$marker*" }) }
function Wait-Godot($marker, $sec) { for ($i = 0; $i -lt $sec * 4; $i++) { $f = Find-Godot $marker; if ($f.Count -gt 0) { return $f }; Start-Sleep -Milliseconds 250 }; return @() }
$common = @("--headless", "--path", $root)

# 1. a script that loops forever while printing is killed at -MaxSeconds
$t0 = Get-Date
$out = & powershell -NoProfile -File $guard -Seconds 60 -MaxSeconds 8 -Args (($common + @("--script", "res://tests/fixtures/chatty_forever.gd", "--", "mk1")) -join ",") | Out-String
$code = $LASTEXITCODE
$el = ((Get-Date) - $t0).TotalSeconds
Check "chatty loop killed by -MaxSeconds (exit $code, ${el}s)" ($code -eq 3 -and $out -match "total time limit 8 s" -and $el -lt 40)
Check "  ... and no Godot left" ((Find-Godot "mk1").Count -eq 0)

# 2. killing the guard also kills its Godot
$g = Start-Process powershell -PassThru -WindowStyle Hidden -ArgumentList (@("-NoProfile", "-File", $guard, "-Seconds", "60", "-MaxSeconds", "100", "-Args", (($common + @("--script", "res://tests/fixtures/chatty_forever.gd", "--", "mk2")) -join ",")))
$found = Wait-Godot "mk2" 30
Check "guard started a Godot" ($found.Count -gt 0)
$ids = @($found | ForEach-Object { $_.ProcessId })
Stop-Process -Id $g.Id -Force
Start-Sleep -Seconds 3
$alive = @($ids | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })
Check "killing the guard kills Godot (pids $($ids -join ','))" ($alive.Count -eq 0)
if ($alive.Count -gt 0) { $alive | ForEach-Object { Stop-Process -Id $_ -Force } }

# 3. run_all --budget=5 on a fixture that never ends quits with TIMEOUT
$out = & powershell -NoProfile -File $guard -Seconds 60 -Args (($common + @("--script", "res://tests/run_all.gd", "--", "--budget=5", "--fixture=slow_forever_test", "mk3")) -join ",") | Out-String
Check "run_all --budget=5 prints TIMEOUT and ends" ($out -match "TIMEOUT in fixtures/slow_forever_test.gd" -and $LASTEXITCODE -ne 0)
Check "  ... and no Godot left" ((Find-Godot "mk3").Count -eq 0)

# 4. sweep kills a planted old headless Godot, leaves an --editor one alone
$plant = Start-Process $godot -PassThru -WindowStyle Hidden -ArgumentList ($common + @("--script", "res://tests/fixtures/sleep_forever.gd", "--", "mk4"))
$fake = Join-Path $env:TEMP "Godot_v4.7-fake_editor.exe"
Copy-Item (Get-Command powershell).Source $fake -Force
$ed = Start-Process $fake -PassThru -WindowStyle Hidden -ArgumentList @("-NoProfile", "-Command", "Start-Sleep 90 # --headless --editor mk4ed")
Start-Sleep -Seconds 8     # older than 0.1 min
$null = Wait-Godot "mk4" 20
$dry = & powershell -NoProfile -File $sweep -MinutesOld 0.1 -CommandLineMatch mk4 -DryRun | Out-String
if (-not ($dry -match "would kill")) { Write-Host $dry }
Check "sweep -DryRun lists the planted run but kills nothing" ($dry -match "would kill" -and $dry -match "mk4" -and -not ($dry -match "mk4ed") -and (Get-Process -Id $plant.Id -ErrorAction SilentlyContinue))
$null = & powershell -NoProfile -File $sweep -MinutesOld 0.1 -CommandLineMatch mk4 | Out-String
Start-Sleep -Seconds 2
Check "sweep killed the planted headless Godot" (-not (Get-Process -Id $plant.Id -ErrorAction SilentlyContinue))
Check "sweep left the --editor process alone" ([bool](Get-Process -Id $ed.Id -ErrorAction SilentlyContinue))
Stop-Process -Id $ed.Id -Force -ErrorAction SilentlyContinue
Remove-Item $fake -Force -ErrorAction SilentlyContinue
Get-Process -Id $plant.Id -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host "test_guard: $fails failure(s)"
exit $(if ($fails -eq 0) { 0 } else { 1 })
