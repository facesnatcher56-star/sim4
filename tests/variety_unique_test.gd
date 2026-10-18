extends RefCounted
## VARIETY: the no-clones rule. 500 generated folk are pairwise distinct (weighted perceptual distance >= threshold), births
## and creator rerolls stay distinct from the town, relatives look more alike than strangers yet are still distinguishable,
## saves round-trip without being touched, role outfits apply, the registry sees townies.

const K = preload("res://tests/systems_kit.gd")


func run() -> Array:
	var f: Array = []
	_pairwise(f)
	_family(f)
	_saves(f)
	_roles(f)
	_registry(f)
	return f


func _gen(n: int, seed_value: int) -> Array:
	var g := RandomNumberGenerator.new()
	g.seed = seed_value
	var out: Array = []
	for i in n:
		out.append(Genetics.unique_appearance(out, g))
	return out


func _min_pair(aps: Array) -> float:
	var chs: Array = []
	for a in aps:
		chs.append(GeneticsLook.channels(a))
	var w: Array = GeneticsLook.weights()
	var best := 1.0e9
	for i in chs.size():
		for j in range(i + 1, chs.size()):
			best = minf(best, GeneticsLook.distance_ch(chs[i], chs[j], w))
	return best


func _pairwise(f: Array) -> void:
	K.setup(21, false)
	var aps: Array = _gen(500, 77)
	var thr: float = GeneticsUnique.threshold()
	var m: float = _min_pair(aps)
	K.expect(f, m >= thr, "500 generated folk: closest pair distance %.2f must be >= %.2f" % [m, thr])
	var sigs := {}
	for a in aps:
		sigs[Genetics.signature(a)] = true
	K.expect(f, sigs.size() == 500, "500 distinct signatures (%d)" % sigs.size())
	var again: Array = _gen(60, 77)
	var same := true
	for i in 60:
		same = same and Genetics.signature(again[i]) == Genetics.signature(aps[i])
	K.expect(f, same, "same seed -> same appearances (deterministic)")
	var kinds := {"hair_style": {}, "top": {}, "body_type": {}, "face": {}, "glasses": {}, "hat": {}, "bottom": {}, "shoes": {}}
	for a in aps:
		for k in kinds:
			kinds[k][int(a[k])] = true
	K.expect(f, (kinds["hair_style"] as Dictionary).size() >= 14 and (kinds["top"] as Dictionary).size() == 7 and (kinds["body_type"] as Dictionary).size() == 3 \
		and (kinds["face"] as Dictionary).size() >= 14 and (kinds["bottom"] as Dictionary).size() == 3 and (kinds["shoes"] as Dictionary).size() == 4,
		"all variants get used: %s" % str(kinds.keys().map(func(k): return "%s=%d" % [k, kinds[k].size()])))
	K.teardown()


func _family(f: Array) -> void:
	K.setup(22, false)
	var g := RandomNumberGenerator.new()
	g.seed = 5
	var town: Array = _gen(120, 31)
	var rel_sum := 0.0
	var rel_n := 0
	var worst := 1.0e9
	for fam in 40:
		var pa: Dictionary = Genetics.unique_appearance(town, g)
		town.append(pa)
		var pb: Dictionary = Genetics.unique_appearance(town, g)
		town.append(pb)
		var kids: Array = []
		for k in 3:
			var kid: Dictionary = Genetics.inherit({"appearance": pa, "traits": []}, {"appearance": pb, "traits": []}, g, {"others": town + kids})["appearance"]
			worst = minf(worst, GeneticsUnique.min_distance(kid, GeneticsUnique._channels_of(town + kids)))
			kids.append(kid)
		var members: Array = [pa, pb] + kids
		town.append_array(kids)
		for i in members.size():
			for j in range(i + 1, members.size()):
				rel_sum += Genetics.distance(members[i], members[j])
				rel_n += 1
	K.expect(f, worst >= GeneticsUnique.threshold(), "children are distinct from the whole town (closest %.2f)" % worst)
	var str_sum := 0.0
	var str_n := 0
	for i in 400:
		var a: Dictionary = town[g.randi_range(0, town.size() - 1)]
		var b: Dictionary = town[g.randi_range(0, town.size() - 1)]
		if a != b:
			str_sum += Genetics.distance(a, b)
			str_n += 1
	var rel_avg: float = rel_sum / maxf(rel_n, 1)
	var str_avg: float = str_sum / maxf(str_n, 1)
	K.expect(f, rel_avg < str_avg - 0.4, "relatives resemble each other more than strangers: %.2f < %.2f" % [rel_avg, str_avg])
	print("variety: relatives avg distance %.2f, strangers %.2f" % [rel_avg, str_avg])
	K.teardown()


func _saves(f: Array) -> void:
	K.setup(23, false)
	var a := Folk.create("Twin")
	var b := Folk.create("Twin2")
	b.appearance = a.appearance.duplicate(true)             # saved clones must be left alone
	var ra: Folk = Folk.from_dict(JSON.parse_string(JSON.stringify(a.to_dict())))
	var rb: Folk = Folk.from_dict(JSON.parse_string(JSON.stringify(b.to_dict())))
	K.expect(f, ra.appearance == rb.appearance and Genetics.signature(ra.appearance) == Genetics.signature(a.appearance), "loading never re-rolls a saved look")
	for k in GeneticsLook.INT_KEYS:
		K.expect(f, ra.appearance[k] is int and ra.appearance[k] == a.appearance[k], "int key %s survives JSON" % k)
	# an old-format appearance (8 keys) is upgraded deterministically
	var old := {"skin": "#d9a47f", "hair_style": 2, "hair_color": "#3d281c", "eye_color": "#5b3a22", "shirt": "#4f9ec4", "pants": "#3a4660", "height": 1.0, "build": 1.0}
	var n1: Dictionary = Genetics.normalize(old)
	var n2: Dictionary = Genetics.normalize(old)
	K.expect(f, n1 == n2 and n1.has("top") and n1.has("accent") and int(n1["hair_style"]) == 2 and n1["shirt"] == "#4f9ec4", "legacy appearance upgrades deterministically and keeps its colours")
	K.expect(f, Genetics.signature(Genetics.normalize(n1)) == Genetics.signature(n1), "normalize is idempotent")
	K.teardown()


func _roles(f: Array) -> void:
	K.setup(24, false)
	var g := RandomNumberGenerator.new()
	g.seed = 9
	var town: Array = _gen(30, 3)
	var want := {"barista": [5], "trainer": [0, 1], "librarian": [2, 3], "student": [6], "office": [3, 2], "cashier": [6]}
	for role in want:
		var ap: Dictionary = FolkOutfits.for_role(role, town, g)
		K.expect(f, int(ap["top"]) in want[role], "%s wears one of the role tops (%d)" % [role, int(ap["top"])])
		K.expect(f, GeneticsUnique.is_distinct(ap, town), "%s staff look is distinct from the town" % role)
		town.append(ap)
	var tr: Dictionary = FolkOutfits.for_role("trainer", [], g)
	K.expect(f, int(tr["bottom"]) in [0, 1] and int(tr["shoes"]) == 3, "trainer: sportswear shoes")
	K.expect(f, FolkOutfits.role_for("fitness_coach", "adult") == "trainer" and FolkOutfits.role_for("", "teen") == "student", "career / stage -> role")
	K.teardown()


func _registry(f: Array) -> void:
	K.setup(25, false)
	Genetics.seed_rng(8)
	Story.generate_townies(14)
	var aps: Array = []
	for t in Story.alive_townies():
		aps.append(t["appearance"])
	K.expect(f, aps.size() >= 14, "townies exist (%d)" % aps.size())
	K.expect(f, _min_pair(aps) >= GeneticsUnique.threshold(), "generated townies are pairwise distinct (closest %.2f)" % _min_pair(aps))
	K.expect(f, GeneticsUnique.registry().size() >= aps.size(), "registry sees every townie")
	var before: int = Story.alive_townies().size()
	var extra: Dictionary = Story.add_townie()
	K.expect(f, Story.alive_townies().size() == before + 1 and GeneticsUnique.min_distance(extra["appearance"], GeneticsUnique._channels_of(aps)) >= GeneticsUnique.threshold(),
		"a new townie is distinct from the existing ones")
	K.teardown()
