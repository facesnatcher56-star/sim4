extends RefCounted
## Not a test (no _test suffix: not discovered by run_all): times the crime event handlers on a 200-townie town, the single hits of 300-500 ms in the benchmark.
##   powershell -File tools/godot_guard.ps1 -Seconds 120 -Args "--headless,--path,.,--script,res://tests/run_one.gd,--,crime_cost_probe"

const C = preload("res://tests/crime_kit.gd")
const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	C.town(200)
	var lot := "town:3"
	for round in 3:
		var t0 := Time.get_ticks_usec()
		var off: int = CrimePetty._offender(lot, "vandalism")
		var t1 := Time.get_ticks_usec()
		CrimePetty.commit("vandalism", off, lot)
		var t2 := Time.get_ticks_usec()
		var b: int = CrimeBurglary.pick_burglar(lot)
		var t3 := Time.get_ticks_usec()
		CrimeBurglary.attempt(lot, true, true, b)
		var t4 := Time.get_ticks_usec()
		var r: float = CrimePressure.risk(int(C.ids()[0]))
		var t5 := Time.get_ticks_usec()
		var tl: Array = CrimePerson.townies_only()
		var t6 := Time.get_ticks_usec()
		print("COST round %d: offender %d us, commit %d us, pick_burglar %d us, attempt(stat) %d us, risk %d us (%.2f), townies_only %d us (%d)" % [round, t1 - t0, t2 - t1, t3 - t2, t4 - t3, t5 - t4, r, t6 - t5, tl.size()])
	K.teardown()
	return []
