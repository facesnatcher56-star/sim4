<#
 Source guard of the heritage rule (docs/ONE_CHARACTER_PLAN.md R13): heritage must never set income, wages, hiring, justice, crime or a district's
 roughness. Greps the money, career, justice, crime, district and storyteller scripts for the word and fails on any hit.
   Usage: powershell -File tools/heritage_guard.ps1
#>
$root = Split-Path -Parent $PSScriptRoot
$patterns = @("economy*.gd","career*.gd","justice*.gd","crime*.gd","solo_districts.gd","solo_pressure.gd","solo_crews.gd","police*.gd","housing_props.gd","market_*.gd","bank_*.gd","storyteller*.gd","incident_risk.gd")
$hits = @()
foreach ($p in $patterns) {
	foreach ($f in Get-ChildItem -Path (Join-Path $root "scripts") -Recurse -Filter $p -ErrorAction SilentlyContinue) {
		$m = Select-String -Path $f.FullName -Pattern "heritage" -SimpleMatch -CaseSensitive:$false
		foreach ($x in $m) { $hits += "$($f.Name):$($x.LineNumber): $($x.Line.Trim())" }
	}
}
if ($hits.Count -gt 0) { Write-Output "FAIL heritage appears in a money / work / justice / crime / district script:"; $hits; exit 1 }
Write-Output "ok   no heritage in the economy, careers, justice, crime and district scripts"
