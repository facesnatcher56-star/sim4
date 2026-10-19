extends RefCounted
## Task 12.3 on the real map: the stations are lots, the response time follows distance, traffic, staffing from the budget, other calls and the phone line;
## the fire brigade, the ambulance and the patrol car use it; far patients feel it.

const Kit = preload("res://tests/hood_kit.gd")

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	var folk: Array = Kit.new_game("small")
	StoryPacing.enabled = false
	CityState.reset()
	UtilityEvents.dice_on = false
	Kit.set_time(3, 13)
	Weather.force("sunny")
	_check(CityServices.map_ready(), "the stations are lots of this map")
	for s in ["fire", "ambulance", "police"]:
		_check(not Neighborhood.lot(str(CityServices.station(s)["lot"])).is_empty(), "the %s station is a real lot (%s)" % [s, CityServices.station(s)["lot"]])
	# --- the numbers
	var near: Dictionary = CityServices.estimate("ambulance", "hospital")
	var far: Dictionary = CityServices.estimate("ambulance", "school")
	var home: Dictionary = CityServices.estimate("ambulance", "home")
	_check(float(near["minutes"]) < float(far["minutes"]) and float(near["tiles"]) < float(far["tiles"]), "a call next to the station is answered sooner (%.1f vs %.1f min)" % [near["minutes"], far["minutes"]])
	print("  [city] ambulance to home %.1f min, to school %.1f min; fire engine to home %.1f min; patrol car to home %.1f min" % [home["minutes"], far["minutes"], CityServices.estimate("fire", "home")["minutes"], CityServices.estimate("police", "home")["minutes"]])
	Kit.set_time(3, 8)
	var rush: float = float(CityServices.estimate("fire", "school")["minutes"])
	Kit.set_time(3, 3)
	var night: float = float(CityServices.estimate("fire", "school")["minutes"])
	_check(rush > night, "rush-hour traffic slows the engine (%.1f vs %.1f min)" % [rush, night])
	var base: float = float(CityServices.estimate("fire", "home")["minutes"])
	CityBudget.set_funding("fire", 0.5)
	_check(float(CityServices.estimate("fire", "home")["minutes"]) > base, "a starved fire budget means a slower turnout")
	CityBudget.set_funding("fire", 1.5)
	_check(float(CityServices.estimate("fire", "home")["minutes"]) < base, "a generous one a faster turnout")
	CityBudget.set_funding("fire", 1.0)
	_check(float(CityServices.estimate("fire", "home", {"no_phone": true})["minutes"]) > base + 5.0, "no phone line: somebody has to raise the alarm another way")
	Utilities.begin("power", "north", 2.0, "fault", {"silent": true, "apply": false})
	Utilities.finish(Utilities.outage_of("power", "north"))
	# --- units: two engines, a third call waits
	CityServices.reset()
	var e1: Dictionary = CityServices.dispatch("fire", "home")
	var e2: Dictionary = CityServices.dispatch("fire", "home")
	var e3: Dictionary = CityServices.dispatch("fire", "home")
	_check(CityServices.units_out("fire") == 3 and float(e3["parts"]["busy"]) > 0.0 and float(e1["parts"]["busy"]) == 0.0, "with both engines out the third call waits (%s)" % str(e3["parts"]))
	Kit.run(120)
	_check(CityServices.units_out("fire") == 0, "engines come back after the call")
	# --- the fire brigade
	var W = Kit.world()
	var stoves: Array = W.objects_of_def("stove").filter(func(o): return NeighborhoodLots.lot_at(o.tile) == "home")
	_check(not stoves.is_empty(), "the home has a stove")
	if not stoves.is_empty():
		Fire.reset()
		_check(Fire.ignite(stoves[0], "cooking", {"force": true, "quiet": true}), "a fire starts")
		Fire.call_brigade("home", -1)
		var b: Dictionary = Fire.blazes.get("home", {})
		_check(not b.is_empty() and int(b.get("response", -1)) > 0 and int(b["due"]) - int(b["call_min"]) >= int(b["response"]) - 3, "the brigade's delay is the engine's response time (%s)" % str(b.get("response", "none")))
		Fire.reset()
	# --- the ambulance
	var ada: Folk = folk[0]
	Kit.set_time(3, 13)
	CityServices.reset()
	var ok: bool = Hospital.emergency(int(ada.id), 2, "a test")
	_check(ok and not Hospital.patients.has(int(ada.id)) and CityAmbulance.holding(int(ada.id)), "a serious case waits for the ambulance first")
	_check(Kit.has_note("ambulance is on its way"), "the player is told an ambulance is coming")
	var wait: int = int(CityServices.pending[0]["minutes"])
	_check(wait >= 3 and wait <= 40, "the wait is a few minutes (%d)" % wait)
	Kit.run(wait + 2)
	_check(Hospital.patients.has(int(ada.id)) and not CityAmbulance.holding(int(ada.id)), "then the patient is admitted")
	Hospital.discharge(int(ada.id))
	# a mild case goes straight in
	var bo: Folk = folk[1] if folk.size() > 1 else ada
	CityServices.reset()
	Hospital.emergency(int(bo.id), 1, "a scrape")
	_check(Hospital.patients.has(int(bo.id)) and not CityAmbulance.holding(int(bo.id)), "a mild case needs no ambulance")
	Hospital.discharge(int(bo.id))
	# a slow ambulance can make things worse
	CityServices.reset()
	CityServices.cfg()["ambulance"]["worsen_after"] = 0
	CityServices.cfg()["ambulance"]["worsen_chance"] = 1.0
	Hospital.emergency(int(ada.id), 2, "a slow test")
	Kit.run(int(CityServices.pending[0]["minutes"]) + 2)
	_check(int((Hospital.patients.get(int(ada.id), {}) as Dictionary).get("severity", 0)) == 3 and int(CityServices.stats.get("worsened", 0)) == 1, "waiting too long makes it worse")
	# --- far patients
	_check(CityServices.death_mult() > 0.9 and CityServices.death_mult() < 1.15, "at the standard budget far patients are not more or less safe (x%.2f)" % CityServices.death_mult())
	CityBudget.set_funding("health", 0.4)
	var slow: float = CityServices.death_mult()
	CityBudget.set_funding("health", 1.5)
	var fast: float = CityServices.death_mult()
	CityBudget.set_funding("health", 1.0)
	_check(slow > fast and slow > 1.0, "a poorly funded ambulance service costs far townies lives (x%.2f vs x%.2f)" % [slow, fast])
	# --- the police
	CityServices.reset()
	var c: Dictionary = CaseStore.create("burglary", -1, -1, "home:1", {"vhid": 1})
	JusticeState.pending.clear()
	Police.respond(c)
	var due: int = int(JusticeState.pending[JusticeState.pending.size() - 1]["due_min"]) if not JusticeState.pending.is_empty() else -1
	_check(due > SysUtil.now() and int(CityServices.stats.get("calls_police", 0)) == 1, "a crime in progress sends a patrol car from the station")
	# --- save
	var before: String = JSON.stringify(CityState.to_dict())
	CityState.from_dict(JSON.parse_string(before))
	_check(JSON.stringify(CityState.to_dict()) == before, "units out and waiting ambulances survive a JSON round trip")
	Kit.teardown()
	return fails
