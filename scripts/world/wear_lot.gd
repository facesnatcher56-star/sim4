class_name WearLot
extends RefCounted
## Task 41a (view only): turns a lot's wear level (0..1) into dressing. `plan(lot_id, wear)` is the pure part (reads World floors / walls, deterministic by lot id, no
## rng of the game): how much litter, which tags where, cracks, weed clumps, dead patches, door stains, boarded windows. Densities come from data/district_dressing.json
## "wear_map" through WearRules.density, so a higher wear level only ever adds things. `build(parent, plan)` makes the nodes: MultiMeshes for litter and grass,
## a few Forward+ decals (capped). WearView calls it for lots near the camera only.

const OUTDOOR := ["sidewalk", "asphalt", "grass", "lawn", "dirt", "concrete", "stone", "sand", "crosswalk"]
const YARD := ["grass", "lawn", "dirt"]
const WALKWAY := ["sidewalk", "asphalt", "concrete", "stone", "crosswalk"]


static func _seed_of(lot_id: String) -> int:
	return lot_id.hash() & 0x7FFFFFFF


static func plan(lot_id: String, wear: float) -> Dictionary:
	var out := {"lot": lot_id, "wear": wear, "litter": [], "tags": [], "cracks": [], "stains": [], "weed_centres": [], "weed_points": [], "dead_centres": [],
		"boards": [], "bars": [], "yard_tiles": 0}
	var rc := NeighborhoodLots.rect_of(lot_id)
	if wear <= 0.0 or rc.size == Vector2i.ZERO:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_of(lot_id)
	var ring := _ring_tiles(rc)
	var yard := _yard_tiles(rc)
	out["yard_tiles"] = yard.size()
	# litter: along the kerb / pavement ring, and a little inside the yard
	var n_ring := int(round(float((ring["walk"] as Array).size()) * WearRules.density("litter_ring", wear)))
	var pool: Array = (ring["walk"] as Array) if not (ring["walk"] as Array).is_empty() else (ring["all"] as Array)
	for i in n_ring:
		var t: Vector2i = pool[rng.randi() % pool.size()]
		out["litter"].append(_litter_at(rng, t))
	var n_yard := int(round(yard.size() * WearRules.density("litter_yard", wear)))
	for i in n_yard:
		out["litter"].append(_litter_at(rng, yard[rng.randi() % yard.size()]))
	# yard: weed clumps (a clump is a cluster of grass), loose weeds, dead patches
	if not yard.is_empty():
		for i in int(round(yard.size() * WearRules.density("weed_clumps_yard", wear))):
			var t: Vector2i = yard[rng.randi() % yard.size()]
			out["weed_centres"].append(Vector2(t.x + rng.randf(), t.y + rng.randf()))
		for i in int(round(yard.size() * WearRules.density("weeds_yard", wear))):
			var t2: Vector2i = yard[rng.randi() % yard.size()]
			out["weed_points"].append(Vector2(t2.x + rng.randf(), t2.y + rng.randf()))
		for i in int(round(yard.size() / 100.0 * WearRules.density("dead_patches_100_yard", wear))):
			var t3: Vector2i = yard[rng.randi() % yard.size()]
			out["dead_centres"].append(Vector2(t3.x + 0.5, t3.y + 0.5))
	# cracks on the pavement / road ring
	var cap := int(WearRules.density("decal_cap", 1.0))
	for i in int(round(float((ring["walk"] as Array).size()) * WearRules.density("cracks_ring", wear))):
		if (ring["walk"] as Array).is_empty() or out["cracks"].size() >= cap / 2:
			break
		var t4: Vector2i = ring["walk"][rng.randi() % (ring["walk"] as Array).size()]
		out["cracks"].append({"tex": "crack", "pos": Vector3(t4.x + 0.5, 0.4, t4.y + 0.5), "size": Vector3(3.0, 1.0, 3.0), "spin": rng.randf() * 180.0})
	# tags on the outer walls
	var runs := _outer_runs(rc)
	var tag_names := GraffitiTex.names()
	var n_tags := mini(int(round(float(runs.size()) * WearRules.density("tags_per_run", wear))), cap / 3)
	var order: Array = range(runs.size())
	for i in range(order.size() - 1, 0, -1):          # seeded shuffle
		var j := rng.randi() % (i + 1)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	for k in mini(n_tags, order.size()):
		var r: Dictionary = runs[order[k]]
		var w: float = clampf(float(r["len"]) - 0.6, 2.0, 3.6)
		var horizontal: bool = bool(r["horizontal"])
		var nm: String = tag_names[(k + int(rng.randi() % 3)) % tag_names.size()]
		var mid: Vector2 = r["mid"]
		var out_off: float = 0.11 * float(r["side"])
		var pos := Vector3(mid.x, 0.75, mid.y + out_off) if horizontal else Vector3(mid.x + out_off, 0.75, mid.y)
		out["tags"].append({"tex": nm, "face": "az" if horizontal else "ax", "pos": pos, "size": Vector3(w, 0.25, w / 2.667) if horizontal else Vector3(w / 2.667, 0.25, w),
			"spin": 0.0 if float(r["side"]) < 0.0 else 180.0})
	# stains where people come and go: in front of the lot's doors
	var doors := _doors(rc)
	var n_st := int(round(WearRules.density("door_stains", wear)))
	for i in mini(n_st, doors.size() * 2):
		var d: Dictionary = doors[i % doors.size()]
		out["stains"].append({"tex": "stain" if i % 2 == 0 else "grime", "pos": Vector3(d["out"].x, 0.4, d["out"].y), "size": Vector3(1.8 + 0.4 * (i % 2), 1.0, 1.6), "spin": rng.randf() * 90.0})
	# boarded / barred windows
	var wins := _windows(rc)
	var frac := WearRules.density("boards_windows", wear)
	for i in wins:
		if frac > 0.0 and WearRules.hash01(i, lot_id.hash() & 0xFFFF, 3) < frac:
			(out["boards"] if WearRules.hash01(i, 7, 5) < 0.5 else out["bars"]).append(i)
	return out


static func _litter_at(rng: RandomNumberGenerator, t: Vector2i) -> Dictionary:
	var kinds := ["paper", "paper", "paper", "can", "can", "bottle", "bag", "newspaper"]
	return {"kind": kinds[rng.randi() % kinds.size()], "pos": Vector3(t.x + rng.randf(), 0.0, t.y + rng.randf()), "yaw": rng.randf() * 360.0, "scale": rng.randf_range(0.8, 1.25), "tone": rng.randf()}


## Tiles in a 2-tile band around the rect: {walk: pavement / road tiles, all: any outdoor tile}.
static func _ring_tiles(rc: Rect2i) -> Dictionary:
	var walk: Array = []
	var all: Array = []
	var g := rc.grow(2)
	for y in range(g.position.y, g.end.y):
		for x in range(g.position.x, g.end.x):
			var t := Vector2i(x, y)
			if rc.grow(-2).has_point(t):
				continue
			if not World.in_bounds(t):
				continue
			var ft := World.get_floor(t)
			if ft in WALKWAY:
				walk.append(t)
			if ft in OUTDOOR:
				all.append(t)
	return {"walk": walk, "all": all}


static func _yard_tiles(rc: Rect2i) -> Array:
	var out: Array = []
	for y in range(rc.position.y, rc.end.y):
		for x in range(rc.position.x, rc.end.x):
			var t := Vector2i(x, y)
			if World.get_floor(t) in YARD and World.object_at(t) == null and World.rooms.is_outdoor(t):
				out.append(t)
	return out


## Runs of plain wall edges on the outside of the lot's buildings: {horizontal, mid: Vector2 (world), len, side: -1 / +1 (which way is outdoors)}.
static func _outer_runs(rc: Rect2i) -> Array:
	var out: Array = []
	var edges: Dictionary = {}
	for e in World.walls:
		if str(World.walls[e]) != "wall" or not rc.has_point(Vector2i(e.x, e.y)):
			continue
		var a := Vector2i(e.x, e.y)
		var b := Vector2i(e.x, e.y - 1) if e.z == 0 else Vector2i(e.x - 1, e.y)
		var a_out: bool = World.rooms.is_outdoor(a)
		var b_out: bool = World.rooms.is_outdoor(b)
		if a_out == b_out:
			continue
		edges[e] = 1.0 if a_out else -1.0           # +1: outdoors is the (x, y) side, -1: the (x - 1 / y - 1) side
	var seen: Dictionary = {}
	for e in edges:
		if seen.has(e):
			continue
		var step := Vector3i(1, 0, 0) if e.z == 0 else Vector3i(0, 1, 0)
		var first: Vector3i = e
		while edges.has(first - step) and edges[first - step] == edges[e]:
			first -= step
		var n := 0
		var cur: Vector3i = first
		while edges.has(cur) and edges[cur] == edges[e]:
			seen[cur] = true
			n += 1
			cur += step
		if n < 3:
			continue
		var horizontal: bool = e.z == 0
		var mid := Vector2(first.x + n * 0.5, first.y) if horizontal else Vector2(first.x, first.y + n * 0.5)
		out.append({"horizontal": horizontal, "mid": mid, "len": float(n), "side": float(edges[e])})
	out.sort_custom(func(a, b): return a["mid"].x + a["mid"].y * 1000.0 < b["mid"].x + b["mid"].y * 1000.0)
	return out


static func _doors(rc: Rect2i) -> Array:
	var out: Array = []
	for e in World.walls:
		if str(World.walls[e]) != "door" or not rc.has_point(Vector2i(e.x, e.y)):
			continue
		var a := Vector2i(e.x, e.y)
		var b := Vector2i(e.x, e.y - 1) if e.z == 0 else Vector2i(e.x - 1, e.y)
		var o := a if World.rooms.is_outdoor(a) else (b if World.rooms.is_outdoor(b) else Vector2i(-1, -1))
		if o.x >= 0 and World.rooms.is_outdoor(a) != World.rooms.is_outdoor(b):
			out.append({"edge": e, "out": Vector2(o.x + 0.5, o.y + 0.5)})
	out.sort_custom(func(a, b): return a["out"].x + a["out"].y * 1000.0 < b["out"].x + b["out"].y * 1000.0)
	return out


## Number of window objects of level 0 in the lot (indices are positions in the position-sorted list DistrictDressing._boards uses).
static func _windows(rc: Rect2i) -> Array:
	var out: Array = []
	var n := 0
	for o in World.all_objects():
		if str(o.def_id) == "window" and o.level == 0 and rc.has_point(o.tile):
			out.append(n)
			n += 1
	return out


# ------------------------------------------------------------------ nodes

static func build(parent: Node3D, p: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "WearLot_%s" % str(p["lot"])
	parent.add_child(root)
	WearProps.build(root, p["litter"], "Litter", 70.0)
	var rc := NeighborhoodLots.rect_of(str(p["lot"])).grow(3)
	if not (p["weed_centres"] as Array).is_empty() or not (p["weed_points"] as Array).is_empty():
		WearYard.build(root, [rc.position.x, rc.position.y, rc.end.x, rc.end.y], {"seed": _seed_of(str(p["lot"])), "centres": p["weed_centres"],
			"weed_points": p["weed_points"], "dead_centres": p["dead_centres"]})
	var forward_plus := RenderingServer.get_current_rendering_method() == "forward_plus"
	if forward_plus:
		for d in (p["cracks"] as Array) + (p["stains"] as Array):
			_decal(root, d, "ay")
		for d in (p["tags"] as Array):
			_decal(root, d, str(d["face"]))
	if not (p["boards"] as Array).is_empty() or not (p["bars"] as Array).is_empty():
		var dd := DistrictDressing.new()
		dd.name = "Boards"
		root.add_child(dd)
		dd.setup_for_lot(str(p["lot"]))
		dd.add_boards({"board": p["boards"], "bars": p["bars"]})
	return root


static func _decal(root: Node3D, d: Dictionary, face: String) -> void:
	var dc := Decal.new()
	dc.texture_albedo = DressingTex.tex(str(d["tex"]))
	dc.size = d["size"]
	dc.position = d["pos"]
	match face:
		"ax": dc.rotation = Vector3(0, 0, PI * 0.5)
		"az": dc.rotation = Vector3(PI * 0.5, 0, 0)
	dc.rotation.y += deg_to_rad(float(d.get("spin", 0.0)))
	dc.upper_fade = 0.05
	dc.lower_fade = 0.05
	dc.normal_fade = 0.1 if face == "ay" else 0.0
	root.add_child(dc)
