class_name SoloCfg
extends RefCounted
## Reader of data/solo.json (the tunable numbers of one-character play). Per-difficulty entries are keyed relaxed / normal / hard.
##   SoloCfg.by_diff("start", "coins")       value for the running game's difficulty
##   SoloCfg.sect("ladder")                   a whole section

static func cfg() -> Dictionary:
	return SysUtil.table("solo")

static func sect(name: String):
	return cfg().get(name, {})

static func diff_id() -> String:
	return Scenario.difficulty if Scenario.difficulty in ["relaxed", "normal", "hard"] else "normal"

## cfg[section][key][difficulty]
static func by_diff(section: String, key: String, diff: String = ""):
	var d: Dictionary = (cfg().get(section, {}) as Dictionary).get(key, {})
	return d.get(diff if diff != "" else diff_id(), d.get("normal", 0))

static func start_coins(diff: String = "") -> int:
	return int(by_diff("start", "coins", diff))

static func rent() -> int:
	return int(by_diff("start", "rent"))

static func ladder() -> Array:
	return cfg().get("ladder", [])

static func rung(id: String) -> Dictionary:
	for r in ladder():
		if str(r["id"]) == id:
			return r
	return {}

## Weekly rent of a rung ("start.rent" = the difficulty's studio rent), bills share, deposit ("rent" = one week).
static func rung_rent(r: Dictionary) -> int:
	var v = r.get("rent", 0)
	return rent() if str(v) == "start.rent" else int(v)

static func rung_deposit(r: Dictionary) -> int:
	var v = r.get("deposit", 0)
	return rung_rent(r) if str(v) == "rent" else int(v)

static func rung_bills(r: Dictionary) -> int:
	return int(r.get("bills", 0))
