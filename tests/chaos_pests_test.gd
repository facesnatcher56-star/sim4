extends RefCounted
## Household chaos (task 07), roaches: only a messy home can get them, they grow while it stays messy (spoiled food, infestation buff,
## sickness at the worst), cleaning and traps make them die back, the exterminator clears them and keeps them away for a while, saved/loaded.

const K = preload("res://tests/systems_kit.gd")
const C = preload("res://tests/chaos_kit.gd")

func run() -> Array:
	var f: Array = []
	_gate(f)
	_growth(f)
	_fixes(f)
	return f

func _make_messy(h: Dictionary, on: bool) -> void:
	for id in ["sink", "stove", "counter"]:
		WorldIface.state_set(h["objs"][id], "dirtiness", 8.0 if on else 0.0)
	WorldIface.state_set(h["objs"]["fridge"], "spoiled", 0.0)
	if not on:
		WorldIface.state_set(h["objs"]["fridge"], "stock", 0.0)       # an empty fridge cannot spoil overnight

func _gate(f: Array) -> void:
	var h: Dictionary = C.setup()
	var subj := IncidentSubject.of_household(1)
	_make_messy(h, false)
	K.expect(f, Incidents.effective_rate("roach_infestation", subj) == 0.0, "a clean home gets no roaches")
	_make_messy(h, true)
	K.expect(f, absf(Incidents.effective_rate("roach_infestation", subj) - 1.2) < 0.001 or Incidents.effective_rate("roach_infestation", subj) > 1.0, "a messy home can: %.2f a year" % Incidents.effective_rate("roach_infestation", subj))
	var r: Dictionary = Incidents.force("roach_infestation", {"lot": "home:1", "outcome": 0})
	K.expect(f, bool(r["ok"]) and absf(ChaosState.pest_level(1) - 0.25) < 0.001, "a first sighting (level 0.25)")
	K.expect(f, h["ada"].has_buff("roaches_seen") and not h["ada"].has_buff("pest_trouble"), "seen, not yet infested")
	K.expect(f, K.has_note("exterminator") and K.has_note("traps"), "told what to do")
	K.expect(f, Incidents.effective_rate("roach_infestation", subj) == 0.0, "no second incident while they are already there")
	K.teardown()

func _growth(f: Array) -> void:
	var h: Dictionary = C.setup()
	var ada: Folk = h["ada"]
	_make_messy(h, true)
	Incidents.force("roach_infestation", {"lot": "home:1", "outcome": 0})
	var fridge = h["objs"]["fridge"]
	C.days(3)
	K.expect(f, ChaosState.pest_level(1) >= 0.5 and ada.has_buff("pest_trouble"), "three messy days: infested (%.2f)" % ChaosState.pest_level(1))
	K.expect(f, float(WorldIface.state_get(fridge, "spoiled", 0.0)) > 0.0, "the food is spoiled by roaches")
	K.expect(f, K.has_note("taken over"), "an infestation notice")
	C.days(5)
	K.expect(f, ChaosState.pest_level(1) <= 1.0 and ChaosState.pest_level(1) >= 0.85, "left alone they take over (%.2f)" % ChaosState.pest_level(1))
	K.teardown()

func _fixes(f: Array) -> void:
	var h: Dictionary = C.setup()
	var ada: Folk = h["ada"]
	_make_messy(h, false)
	Incidents.force("roach_infestation", {"lot": "home:1", "outcome": 0})
	var coins: int = Economy.balance(1)
	C.ev("set_roach_traps", ada)
	K.expect(f, ChaosState.pest_level(1) == 0.0 or not ChaosState.pests.has("1"), "a set of traps clears a first sighting")
	K.expect(f, not ada.has_buff("roaches_seen"), "marker gone")
	# a clean home loses them by itself
	ChaosState.pest_rec(1)["level"] = 0.4
	for d in 8:
		_make_messy(h, false)                      # somebody keeps cleaning (food spoils on its own a little every day)
		C.days(1)
	K.expect(f, ChaosState.pest_level(1) == 0.0 and K.has_note("roaches are gone"), "a clean kitchen starves them out (%.2f, mess %d)" % [ChaosState.pest_level(1), ChaosConds.mess_score(1)])
	# the exterminator
	_make_messy(h, true)
	ChaosState.pest_rec(1)["level"] = 0.7
	ChaosClock.sync_markers(1)
	var bal: int = Economy.balance(1)
	C.ev("call_exterminator", ada)
	K.expect(f, Economy.balance(1) == bal - 80, "the exterminator costs 80 coins")
	C.minutes(130)
	K.expect(f, ChaosState.pest_level(1) == 0.0 and not ada.has_buff("pest_trouble"), "they cleared the house")
	var subj := IncidentSubject.of_household(1)
	K.expect(f, Incidents.effective_rate("roach_infestation", subj) < 1.2 * 0.2, "and the house stays protected for a while (%.2f)" % Incidents.effective_rate("roach_infestation", subj))
	C.days(3)
	K.expect(f, ChaosState.pest_level(1) == 0.0, "a messy but protected house does not grow roaches")
	# save and load
	var snap: Dictionary = Incidents.to_dict()
	var before: Dictionary = ChaosState.to_dict()
	Incidents.from_dict(snap)
	K.expect(f, K.deep_eq(before, ChaosState.to_dict()), "pest state survives save and load")
	K.expect(f, coins > 0, "coins sanity")
	K.teardown()
