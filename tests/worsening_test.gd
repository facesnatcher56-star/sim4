extends RefCounted
## Task 34: only things that really get worse with time worsen while waiting; a sprain needs no ambulance and no ambulance bill.

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
	var ada: Folk = folk[0]
	# the table: every cause says why
	for reason in ["bleeding", "a heart attack", "choking", "smoke", "a bad fall", "nearly drowning", "an electric shock"]:
		var z: Dictionary = Worsening.cause(reason)
		_check(bool(z.get("worsens", false)) and str(z.get("why", "")) != "", "%s worsens with time and says why" % reason)
	for reason in ["a twisted ankle", "a bad strain", "a scraped knee", "the flu", "a cold", "a scuffle"]:
		_check(not Worsening.worsens(reason) and not Worsening.needs_ambulance(reason, 3), "%s never worsens by waiting and needs no ambulance" % reason)
	# a sprain, 30 minutes of waiting: no ambulance, no worsening, no ambulance call
	CityServices.reset()
	Hospital.emergency(int(ada.id), 2, "a twisted ankle")
	_check(not CityAmbulance.holding(int(ada.id)) and CityServices.pending.is_empty(), "a sprain waits for no ambulance")
	_check(Hospital.patients.has(int(ada.id)) and int(Hospital.patients[int(ada.id)]["severity"]) == 1 and int(Hospital.patients[int(ada.id)]["bill"]) < 100, "a sprain is a short, cheap clinic visit (not a 700-coin stay)")
	Kit.run(30)
	_check(int(CityServices.stats.get("calls_ambulance", 0)) == 0 and int(CityServices.stats.get("worsened", 0)) == 0, "no ambulance call and nothing got worse")
	Hospital.discharge(int(ada.id))
	# bleeding with a slow ambulance does get worse
	CityServices.reset()
	var bl: Dictionary = Worsening.cause("bleeding")
	var keep_a = bl["worsen_after"]
	var keep_c = bl["worsen_chance"]
	bl["worsen_after"] = 0                      # the data tables are shared by every test of the process: restored below
	bl["worsen_chance"] = 1.0
	Hospital.emergency(int(ada.id), 2, "bleeding")
	_check(CityAmbulance.holding(int(ada.id)), "bleeding gets an ambulance")
	Kit.run(int(CityServices.pending[0]["minutes"]) + 2)
	bl["worsen_after"] = keep_a
	bl["worsen_chance"] = keep_c
	_check(int((Hospital.patients.get(int(ada.id), {}) as Dictionary).get("severity", 0)) == 3 and int(CityServices.stats.get("worsened", 0)) == 1, "bleeding got worse while waiting")
	Hospital.discharge(int(ada.id))
	# walking on a sprain slows healing; resting does not
	Health.heal(ada)
	HealthInjury.injure(ada, 1, "a twisted ankle")
	var r: Dictionary = Health.rec_of(int(ada.id))
	var walk := Interaction.new()
	walk.state = "walking"
	ada.current = walk
	var before: float = _left(ada)
	HealthInjury.tick_minute(ada, r)
	_check(_left(ada) > before, "walking on a sprain makes it heal slower")
	ada.current = null
	before = _left(ada)
	HealthInjury.tick_minute(ada, r)
	_check(is_equal_approx(_left(ada), before), "standing still does not make a sprain worse")
	Kit.teardown()
	return fails

func _left(f: Folk) -> float:
	for b in f.buffs:
		if str(b["id"]) == "injured":
			return float(b["remaining"])
	return 0.0
