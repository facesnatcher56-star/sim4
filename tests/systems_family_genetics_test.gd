extends RefCounted
## Genetics: the appearance contract, linear-RGB skin blending with bounded mutation, hair / eye dominance, trait inheritance
## statistics (35% per parent trait), body noise ranges, UI colour, JSON roundtrip through Folk.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_contract(f)
	_skin(f)
	_dominance(f)
	_traits(f)
	_body_and_people(f)
	_folk_roundtrip(f)
	return f

func _contract(f: Array) -> void:
	K.setup(7, false)
	Genetics.seed_rng(11)
	var ap: Dictionary = Genetics.random_appearance()
	K.expect(f, Genetics.is_valid(ap), "random appearance has every contract key: %s" % str(ap.keys()))
	K.expect(f, ap["skin"] is String and str(ap["skin"]).begins_with("#") and str(ap["skin"]).length() == 7, "skin is #rrggbb: %s" % str(ap["skin"]))
	K.expect(f, int(ap["hair_style"]) >= 0 and int(ap["hair_style"]) <= 5, "hair_style in 0..5")
	K.expect(f, float(ap["height"]) >= 0.9 and float(ap["height"]) <= 1.1 and float(ap["build"]) >= 0.9 and float(ap["build"]) <= 1.1, "height / build in 0.9..1.1")
	K.expect(f, ap["color"] == ap["shirt"], "`color` mirrors the shirt (UIU.folk_color understands it)")
	Genetics.seed_rng(99)
	var a1: Dictionary = Genetics.random_appearance()
	Genetics.seed_rng(99)
	K.expect(f, a1 == Genetics.random_appearance(), "seeded rng is deterministic")
	var seen: Dictionary = {}
	for i in 60:
		seen[Genetics.random_appearance()["skin"]] = true
	K.expect(f, seen.size() > 20, "skin tones vary (%d distinct)" % seen.size())
	# the global gameplay rng is never consumed by appearance
	SysUtil.seed_rng(5)
	var before: int = SysUtil.rng.state
	Genetics.random_appearance()
	Genetics.inherit(Folk.create("A"), Folk.create("B"))
	K.expect(f, SysUtil.rng.state == before, "appearance does not perturb SysUtil.rng")
	var folk := Folk.create("Zed")
	K.expect(f, Genetics.is_valid(folk.appearance), "Folk.create gives every folk an appearance")
	var bare := Folk.new("Bare")
	K.expect(f, bare.appearance.is_empty() and Genetics.is_valid(Genetics.ensure(bare)), "ensure() fills a missing appearance")
	K.teardown()

func _skin(f: Array) -> void:
	K.setup(8, false)
	Genetics.seed_rng(2024)
	var pa: Dictionary = Genetics.random_appearance()
	var pb: Dictionary = Genetics.random_appearance()
	pa["skin"] = "#f6d7c3"
	pb["skin"] = "#4a2a1c"
	var la: Color = Genetics.hex_to_linear("#f6d7c3")
	var lb: Color = Genetics.hex_to_linear("#4a2a1c")
	var tol: float = float(SimEnv.data().get_table("genetics")["inherit"]["color_mutation_max"]) + 0.012
	var out_of_range: int = 0
	var sums: Array = [0.0, 0.0, 0.0]
	var distinct: Dictionary = {}
	var n: int = 1000
	for i in n:
		var child: Dictionary = Genetics.inherit({"traits": [], "appearance": pa}, {"traits": [], "appearance": pb})
		var sk: String = str(child["appearance"]["skin"])
		distinct[sk] = true
		var lc: Color = Genetics.hex_to_linear(sk)
		for ch in 3:
			var lo: float = minf(la[ch], lb[ch]) - tol
			var hi: float = maxf(la[ch], lb[ch]) + tol
			if lc[ch] < lo or lc[ch] > hi:
				out_of_range += 1
			sums[ch] += lc[ch]
	K.expect(f, out_of_range == 0, "child skin stays within the parents' range +- mutation (%d channel values outside, %d children)" % [out_of_range, n])
	for ch2 in 3:
		var mid: float = (la[ch2] + lb[ch2]) * 0.5
		K.expect(f, absf(sums[ch2] / float(n) - mid) < 0.03, "blend is centred on the linear-RGB midpoint (channel %d: mean %.3f vs %.3f)" % [ch2, sums[ch2] / float(n), mid])
	K.expect(f, distinct.size() > 100, "children differ from each other (%d distinct skin tones)" % distinct.size())
	# identical parents: child is the same tone up to mutation
	var same_ok: bool = true
	for i2 in 100:
		var c2: Dictionary = Genetics.inherit({"traits": [], "appearance": pa}, {"traits": [], "appearance": pa})
		var d: Color = Genetics.hex_to_linear(str(c2["appearance"]["skin"]))
		for ch3 in 3:
			if absf(d[ch3] - la[ch3]) > tol:
				same_ok = false
	K.expect(f, same_ok, "identical parents give a child within mutation of their tone")
	# linear blending: the midpoint of black and white is NOT sRGB #808080
	var mid_hex: String = Genetics.blend_hex("#000000", "#ffffff", 0.5)
	K.expect(f, mid_hex != "#808080" and Color.html(mid_hex).r > 0.6, "blend happens in linear space (black+white -> %s)" % mid_hex)
	K.teardown()

func _dominance(f: Array) -> void:
	K.setup(9, false)
	Genetics.seed_rng(31)
	var pa: Dictionary = Genetics.random_appearance()
	var pb: Dictionary = Genetics.random_appearance()
	pa["hair_color"] = "#1e1a18"    # black, dominance 5
	pb["hair_color"] = "#ece3c8"    # platinum, dominance 1
	pa["eye_color"] = "#5b3a22"     # brown, dominance 5
	pb["eye_color"] = "#3f72b8"     # blue, dominance 1.2
	var black: int = 0
	var platinum: int = 0
	var brown_eyes: int = 0
	var blue_eyes: int = 0
	for i in 1000:
		var c: Dictionary = Genetics.inherit({"traits": [], "appearance": pa}, {"traits": [], "appearance": pb})["appearance"]
		if c["hair_color"] == pa["hair_color"]:
			black += 1
		elif c["hair_color"] == pb["hair_color"]:
			platinum += 1
		if c["eye_color"] == pa["eye_color"]:
			brown_eyes += 1
		elif c["eye_color"] == pb["eye_color"]:
			blue_eyes += 1
	K.expect(f, black > platinum * 3, "dominant hair colour wins most of the time (black %d vs platinum %d)" % [black, platinum])
	K.expect(f, brown_eyes > blue_eyes * 2, "dominant eye colour wins most of the time (brown %d vs blue %d)" % [brown_eyes, blue_eyes])
	K.expect(f, platinum > 20 and blue_eyes > 20, "recessive colours still show up (%d platinum, %d blue)" % [platinum, blue_eyes])
	K.teardown()

func _traits(f: Array) -> void:
	K.setup(10, false)
	Genetics.seed_rng(77)
	var a := {"traits": ["neat", "social"], "appearance": {}}
	var b := {"traits": ["lazy", "gamer"], "appearance": {}}
	var n: int = 1000
	var from_parents: int = 0
	var slots: int = 0
	var with_extra: int = 0
	var cap_ok: bool = true
	var pool: Array = ["neat", "social", "lazy", "gamer"]
	for i in n:
		var tr: Array = Genetics.inherit(a, b)["traits"]
		slots += 4
		var extra: int = 0
		for t in tr:
			if pool.has(t):
				from_parents += 1
			else:
				extra += 1
		if extra == 1:
			with_extra += 1
		if tr.size() > Aging.trait_slots("adult"):
			cap_ok = false
	var rate: float = float(from_parents) / float(slots)
	K.expect(f, rate > 0.30 and rate < 0.40, "each parent trait is inherited about 35%% of the time (measured %.3f over %d children)" % [rate, n])
	K.expect(f, with_extra > n * 95 / 100, "a random extra trait is added (%d of %d children)" % [with_extra, n])
	K.expect(f, cap_ok, "traits never exceed the adult trait slots")
	# capped by explicit slots
	var capped: bool = true
	for i2 in 200:
		if Genetics.inherit(a, b, null, {"chance": 1.0, "cap": 2})["traits"].size() > 2:
			capped = false
	K.expect(f, capped, "cap option limits the number of traits")
	var all4: Array = Genetics.inherit(a, b, null, {"chance": 1.0, "cap": 4, "extra": 0})["traits"]
	K.expect(f, all4.size() == 4, "chance 1.0 passes every parent trait: %s" % str(all4))
	var none: Array = Genetics.inherit(a, b, null, {"chance": 0.0, "extra": 0})["traits"]
	K.expect(f, none.is_empty(), "chance 0.0 passes none")
	# babies' pool is capped by the data-driven teen slots through Aging's call (max_inherited)
	var folk_a := Folk.create("Pa", ["neat", "social"])
	var folk_b := Folk.create("Pb", ["lazy", "gamer"])
	var via_folk: Array = Genetics.inherit(folk_a, folk_b, null, {"chance": 1.0, "cap": 3})["traits"]
	K.expect(f, via_folk.size() == 3, "Folk objects work as parents too: %s" % str(via_folk))
	K.teardown()

func _body_and_people(f: Array) -> void:
	K.setup(12, false)
	Genetics.seed_rng(5)
	var tall := Genetics.random_appearance()
	var small := Genetics.random_appearance()
	tall["height"] = 1.1
	tall["build"] = 1.1
	small["height"] = 0.9
	small["build"] = 0.9
	var all_in: bool = true
	var sum_h: float = 0.0
	for i in 500:
		var c: Dictionary = Genetics.inherit({"traits": [], "appearance": tall}, {"traits": [], "appearance": small})["appearance"]
		if float(c["height"]) < 0.9 or float(c["height"]) > 1.1 or float(c["build"]) < 0.9 or float(c["build"]) > 1.1:
			all_in = false
		sum_h += float(c["height"])
	K.expect(f, all_in, "height / build always stay within 0.9..1.1")
	K.expect(f, absf(sum_h / 500.0 - 1.0) < 0.01, "height is the parent average (%.3f)" % (sum_h / 500.0))
	# UI colour
	var folk := Folk.create("Pip")
	folk.appearance["shirt"] = "#336699"
	K.expect(f, Genetics.ui_color(folk).is_equal_approx(Color.html("#336699")), "ui_color is the shirt colour")
	var bare := Folk.new("Bare")
	var fallback: Color = Genetics.ui_color(bare)
	K.expect(f, fallback.a == 1.0, "ui_color falls back gracefully without an appearance")
	K.expect(f, Genetics.ui_color({"name": "Dict", "appearance": {"shirt": "#ff0000"}}).is_equal_approx(Color.html("#ff0000")), "ui_color accepts dictionaries (townies)")
	# townies and visitors get an appearance
	Story.generate_townies(4)
	var all_have: bool = true
	for t in Story.alive_townies():
		if not Genetics.is_valid(t.get("appearance", {})):
			all_have = false
	K.expect(f, all_have, "every generated townie has an appearance")
	K.teardown()

func _folk_roundtrip(f: Array) -> void:
	K.setup(13, false)
	var folk := Folk.create("Ann", ["neat"])
	var parsed: Variant = JSON.parse_string(JSON.stringify(folk.to_dict()))
	var back: Folk = Folk.from_dict(parsed)
	var diffs: Array = []
	K.expect(f, K.deep_eq(folk.appearance, back.appearance, "appearance", diffs), "appearance survives to_dict / JSON / from_dict: %s" % str(diffs.slice(0, 3)))
	K.expect(f, back.appearance["hair_style"] is int and back.appearance["height"] is float, "types are restored after JSON")
	K.teardown()
