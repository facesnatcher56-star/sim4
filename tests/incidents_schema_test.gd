extends RefCounted
## Incident data: every data/incidents.json + data/incidents/*.json entry and data/death_causes*.json must validate
## (unknown condition / effect / outcome keys, bad scopes, unknown handlers or death causes fail), and the validator itself catches mistakes.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	K.setup()
	IncidentDefs.reset()
	DeathCauses.reset()
	var errs: Array = IncidentDefs.validate_all()
	K.expect(f, errs.is_empty(), "incident data validates: %s" % str(errs))
	K.expect(f, IncidentDefs.ids().size() >= 4 and IncidentDefs.files.size() >= 2, "base file + data/incidents/*.json merged: %s" % str(IncidentDefs.files))
	for id in ["heart_attack", "minor_fall", "found_money", "townie_mishap"]:
		K.expect(f, IncidentDefs.defs.has(id), "seed example '%s' exists" % id)
	var derrs: Array = DeathCauses.validate_all()
	K.expect(f, derrs.is_empty(), "death causes validate: %s" % str(derrs))
	K.expect(f, DeathCauses.has_cause("old age") and DeathCauses.has_cause("heart_attack"), "causes found (old age aliases old_age)")
	# every effect kill in the data names a real cause; every grief tier maps to a buff that exists
	for tier in [1.0, 1.5, 2.0]:
		K.expect(f, not SimEnv.data().buff_def(DeathCauses.grief_buff(tier)).is_empty() or tier == 1.0, "grief buff for strength %.1f exists" % tier)
	# the validator catches mistakes
	var bad := {"label": "x", "scope": "galaxy", "check": "week", "base_rate_per_year": -1, "bogus": 1,
		"conditions": [{"no_such_cond": 1}], "outcomes": [{"weight": 1, "effects": [{"kill": "no_such_cause"}, {"explode": 1}, {"handler": "nope"}], "wat": 2}]}
	var be: Array = IncidentDefs.validate_def("bad", bad)
	var joined: String = " | ".join(be)
	for frag in ["bad scope", "bad check", "base_rate_per_year", "unknown key 'bogus'", "unknown condition key 'no_such_cond'", "unknown death cause", "unknown effect key 'explode'", "unknown handler", "unknown outcome key 'wat'"]:
		K.expect(f, joined.find(frag) >= 0, "validator reports: %s" % frag)
	# the Surprises setting exists in the Gameplay tab with the four levels
	var d: Dictionary = GameSettings.def_of("surprises")
	K.expect(f, not d.is_empty() and d["tab"] == "gameplay" and d["def"] == "rare" and (d["opts"] as Array).size() == 4, "Surprises setting declared")
	K.expect(f, GameSettings.sanitize("surprises", "bogus") == "rare", "bad Surprises value falls back to Rare")
	K.teardown()
	return f
