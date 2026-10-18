extends RefCounted
## HouseGenerator: data/generated_lots.json has every required lot (counts), the schema matches lot_templates.json, the
## generator is deterministic per seed, and the uniqueness gate really rejects a duplicate layout.
const Kit = preload("res://tests/house_kit.gd")

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	var lots: Dictionary = HouseGenerator.lots()
	var by_prefix := {"small_": 0, "medium_": 0, "large_": 0, "classic_": 0, "townie_": 0}
	for id in lots:
		for p in by_prefix:
			if str(id).begins_with(p):
				by_prefix[p] += 1
	_check(by_prefix["small_"] >= 6, "at least 6 small homes (%d)" % by_prefix["small_"])
	_check(by_prefix["medium_"] >= 6, "at least 6 medium homes (%d)" % by_prefix["medium_"])
	_check(by_prefix["large_"] >= 4, "at least 4 large homes (%d)" % by_prefix["large_"])
	_check(by_prefix["classic_"] >= 3, "at least 3 classic-size homes (%d)" % by_prefix["classic_"])
	_check(by_prefix["townie_"] == 3, "3 townie homes (%d)" % by_prefix["townie_"])
	for vt in ["park", "cafe", "gym", "library", "market", "office", "school"]:
		var n := 0
		for id in lots:
			if str(id).begins_with(vt + "_v"):
				n += 1
		_check(n >= 3, "%s has 3 alternate layouts (%d)" % [vt, n])
	_check(HouseGenerator.pool("small").size() >= 6 and HouseGenerator.venue_pool("cafe").size() == 4 and HouseGenerator.venue_pool("cafe")[0] == "cafe", "pool() / venue_pool()")
	_check(HouseGenerator.template("small_01").has("objects") and HouseGenerator.ids().size() == lots.size(), "template(id) / ids() work")
	var home_fp := {"small": 10 * 7, "medium": 14 * 11, "large": 22 * 14, "classic": 16 * 12}
	print("---- generated lots (%d) ----" % lots.size())
	print("%-12s %-5s %-4s %4s %5s %4s %4s %4s %5s" % ["id", "size", "area", "obj", "kinds", "win", "door", "bed", "price"])
	var ids: Array = lots.keys()
	ids.sort()
	for id in ids:
		var t: Dictionary = lots[id]
		for k in ["label", "description", "floors", "walls", "objects", "spawn", "entry", "price"]:
			_check(t.has(k), "%s lacks %s" % [id, k])
		var sh := Kit.shell_of(t)
		var kind := str(t.get("kind", "home"))
		if kind == "home":
			var want: int = home_fp[str(t["size"])]
			_check(sh.size.x * sh.size.y == want, "%s footprint %s is not the %s template footprint (%d tiles)" % [id, str(sh.size), t["size"], want])
		else:
			_check(sh.size == Vector2i(22, 14) or str(t.get("venue", "")) == "park", "%s venue footprint %s" % [id, str(sh.size)])
		var s := Kit.stats(t)
		print("%-12s %-5s %4d %4d %5d %4d %4d %4d %5d" % [id, str(t.get("size", t.get("venue", ""))), sh.size.x * sh.size.y, s["objects"], s["kinds"], s["windows"], s["doors"], s["beds"], int(t["price"])])
	# determinism: the same spec + seed gives the identical template
	var spec: Dictionary = {}
	for sp in HouseGenerator.specs()["homes"]:
		if sp["id"] == "small_02":
			spec = sp
	var a := HouseGenerator.make_home(spec, {})
	var b := HouseGenerator.make_home(spec, {})
	_check(a.has("template") and JSON.stringify(a["template"]) == JSON.stringify(b.get("template", {})), "same seed -> identical layout")
	if a.has("template"):
		var norm: String = JSON.stringify(JSON.parse_string(JSON.stringify(a["template"])))     # ints -> floats like the file
		_check(norm == JSON.stringify(lots.get("small_02", {})), "data/generated_lots.json is up to date with the generator (run tools/gen_houses.gd)")
		# uniqueness gate: with the first result "taken" the generator must come up with a different layout
		var taken := {HouseSignature.plan_sig(a["template"]): "x", HouseSignature.layout_sig(a["template"]): "x"}
		var c := HouseGenerator.make_home(spec, taken)
		_check(c.has("template") and HouseSignature.plan_sig(c["template"]) != HouseSignature.plan_sig(a["template"]), "duplicate floor plan is rejected and replaced")
	return fails
