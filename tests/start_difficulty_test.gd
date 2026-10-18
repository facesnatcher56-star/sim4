extends RefCounted
## Difficulty multipliers (funds / bills / need drain) come from data/scenarios.json and reach Economy and Folk; home size does not
## change the funds; custom households are validated in plain language.

const Kit := preload("res://tests/start_kit.gd")
var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	_funds()
	_bills_and_needs()
	_validation()
	Kit.teardown()
	return fails

func _funds() -> void:
	_check(Scenario.funds_for("solo", "normal") == 4000, "solo normal 4000")
	_check(Scenario.funds_for("solo", "relaxed") == 6000, "solo relaxed x1.5 = 6000 (%d)" % Scenario.funds_for("solo", "relaxed"))
	_check(Scenario.funds_for("solo", "hard") == 2800, "solo hard x0.7 = 2800 (%d)" % Scenario.funds_for("solo", "hard"))
	_check(Scenario.funds_for("sandbox", "normal", 50000) == 50000, "Free Play rich option")
	# home size never changes the money: the same scenario funds on every start
	var amounts := {}
	for start in ["small", "medium", "large", "classic"]:
		Kit.new_game("solo", "normal")
		NewGame.start(Kit.mgr, HouseholdSetup.make_household("solo"), start, {"scenario": "solo", "funds": Scenario.funds_for("solo", "normal")})
		amounts[start] = Economy.balance(1)
	_check(amounts.values().all(func(v): return v == 4000), "funds do not depend on home size: %s" % str(amounts))
	for d in ["relaxed", "normal", "hard"]:
		Kit.new_game("family", d)
		_check(Economy.balance(1) == Scenario.funds_for("family", d), "family %s funds in the economy (%d)" % [d, Economy.balance(1)])
		_check(Scenario.difficulty == d, "difficulty stored: %s" % d)

func _bills_and_needs() -> void:
	var bills := {}
	var drops := {}
	for d in ["relaxed", "normal", "hard"]:
		var folk: Array = Kit.new_game("solo", d)
		bills[d] = Economy.compute_bill(1)
		var f: Folk = folk[0]
		var before: float = f.get_stat_value("hunger")
		f.tick_needs(60.0)
		drops[d] = before - f.get_stat_value("hunger")
	_check(bills["normal"] > 0, "a bill exists on Normal (%d)" % bills["normal"])
	_check(absf(float(bills["relaxed"]) / float(bills["normal"]) - 0.8) < 0.03, "relaxed bills are 80%% (%s)" % str(bills))
	_check(absf(float(bills["hard"]) / float(bills["normal"]) - 1.3) < 0.03, "hard bills are 130%% (%s)" % str(bills))
	_check(drops["normal"] > 0.0, "hunger falls on Normal (%f)" % drops["normal"])
	_check(absf(drops["relaxed"] / drops["normal"] - 0.8) < 0.03, "relaxed needs fall 20%% slower (%s)" % str(drops))
	_check(absf(drops["hard"] / drops["normal"] - 1.2) < 0.03, "hard needs fall 20%% faster (%s)" % str(drops))
	# visitors / townies (no household) are not affected
	var stranger := Folk.create("Stray", [])
	stranger.household_id = 0
	_check(is_equal_approx(stranger.decay_mult("hunger"), 1.0), "difficulty only touches household members")
	# a fresh game without a scenario is back to Normal
	SystemsManager.reset_all()
	_check(Scenario.bill_multiplier() == 1.0 and Scenario.need_drain() == 1.0 and not Scenario.active(), "reset_all clears the scenario")

func _member(nm: String, stage: String, rel: String) -> Dictionary:
	return {"name": nm, "stage": stage, "rel": rel, "traits": HouseholdSetup.random_traits(HouseholdSetup.trait_count(stage)), "aspiration": "",
		"appearance": Genetics.random_appearance()}

func _validation() -> void:
	var ok := {"name": "X", "folk": [_member("A", "adult", "none")]}
	_check(HouseholdSetup.validate(ok) == "", "one adult is fine")
	_check(HouseholdSetup.validate({"name": "X", "folk": []}) != "", "empty household refused")
	var seven: Array = []
	for i in 7:
		seven.append(_member("N%d" % i, "adult", "none"))
	_check(HouseholdSetup.validate({"name": "X", "folk": seven}) != "", "more than 6 refused")
	_check(HouseholdSetup.validate({"name": "X", "folk": seven.slice(0, 6)}) == "", "exactly 6 is fine")
	_check(HouseholdSetup.validate({"name": "X", "folk": [_member("A", "adult", "none"), _member("a", "adult", "none")]}) != "", "duplicate names refused (case-insensitive)")
	_check(HouseholdSetup.validate({"name": "X", "folk": [_member(" ", "adult", "none")]}) != "", "blank name refused")
	_check(HouseholdSetup.validate({"name": "X", "folk": [_member("A", "child", "none")]}) != "", "a lone child needs a grown-up")
	_check(HouseholdSetup.validate({"name": "X", "folk": [_member("A", "teen", "none"), _member("B", "child", "none")]}) != "", "children without an adult refused")
	_check(HouseholdSetup.validate({"name": "X", "folk": [_member("A", "adult", "none"), _member("B", "child", "partner")]}) != "", "child partner refused")
	_check(HouseholdSetup.validate({"name": "X", "folk": [_member("A", "child", "none"), _member("B", "adult", "none"), _member("C", "adult", "child")]}) != "", "adult child of a child refused")
	_check(HouseholdSetup.validate({"name": "X", "folk": [_member("A", "adult", "none"), _member("B", "teen", "child"), _member("C", "elder", "parent")]}) == "", "child + parent relations are fine")
	var few := _member("A", "adult", "none")
	few["traits"] = ["neat"]
	_check(HouseholdSetup.validate({"name": "X", "folk": [few]}) != "", "adults need 3 traits")
	var kid := _member("K", "child", "child")
	_check((kid["traits"] as Array).size() == 2, "children have 2 trait slots")
	_check(HouseholdSetup.validate({"name": "X", "folk": [_member("A", "adult", "none"), kid]}) == "", "child with 2 traits is fine")
