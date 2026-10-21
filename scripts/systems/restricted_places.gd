class_name RestrictedPlaces
extends RefCounted
## Task 53: staff-only parts of public buildings. The front of a police station, courthouse, city hall, hospital, office, works or shelter is
## public; past `public_depth` tiles from the front door, or on any upper floor, is staff only (data/staff_posts.json). Nothing marks it: the pawn
## can walk anywhere. Staff who are really there and notice (Notice) stop them: turn back, say you're meeting someone (lie vs perception),
## or keep going: a guard walks you out, otherwise they call it in (trespassing, seen). People who work there are left alone.
##   RestrictedPlaces.on_minute()   (the pawn only, only on a lot that has a public_depth)

static var asked: Dictionary = {}          # "fid|lot" -> minute they were last stopped
static var allowed: Dictionary = {}        # "fid|lot" -> day a lie got them waved through
static var last_pub: Dictionary = {}       # "fid|lot" -> [tile, minute]: the last public spot inside (staff see you walk past the desk)

static func reset() -> void:
	asked = {}
	allowed = {}
	last_pub = {}

static func cfg() -> Dictionary:
	return SysUtil.table("staff_posts")

static func _line(k: String, n: String) -> String:
	var lines: Array = cfg().get("lines", {}).get(k, [""])
	return str(lines[PlayerPrompt._pick("restricted|" + k, lines.size())]).replace("{n}", n)

## Is this tile (and floor) of the lot staff only?
static func staff_only(lot: String, tile: Vector2i, level: int) -> bool:
	var depth = (cfg().get("public_depth", {}) as Dictionary).get(Venues.type_of_lot(lot), null)
	if depth == null:
		return false
	if level > 0:
		return true
	var fr: Dictionary = StaffPosts.front(lot)
	if fr.is_empty():
		return false
	var rel: Vector2i = tile - (fr["door"] as Vector2i)
	var inward: Vector2i = fr["inward"]
	return rel.x * inward.x + rel.y * inward.y > int(depth)

static func on_minute() -> void:
	var f = SysUtil.folk(Pawn.of())
	if f == null or SysUtil.is_away(f):
		return
	var lot: String = Neighborhood.lot_of(f)
	if lot == "" or not (cfg().get("public_depth", {}) as Dictionary).has(Venues.type_of_lot(lot)):
		return
	if Workplace.lot_of_folk(f) == lot or (f.current != null and not bool(f.current.player)):
		return          # works here, or a system is moving them (a trial, a hospital stay, custody)
	var k: String = "%d|%s" % [int(f.id), lot]
	if int(allowed.get(k, -1)) == SysUtil.day() or SysUtil.now() - int(asked.get(k, -100000)) < int(cfg().get("ask_again_min", 30)):
		return
	if WeatherFolk.is_outside(f):
		return
	if not staff_only(lot, f.tile, int(f.level)):
		last_pub[k] = [f.tile, SysUtil.now()]
		return
	var seen_at: Vector2i = f.tile
	var lp: Array = last_pub.get(k, [])
	if not lp.is_empty() and SysUtil.now() - int(lp[1]) <= 3:
		seen_at = lp[0]          # walking past the front: the staff there see them go through
	last_pub.erase(k)
	var staff: Array = Crowd.staff_folk(lot)
	if staff.is_empty():
		return
	var ids: Array = staff.map(func(s): return int(s.id))
	var nid: int = -1
	for n in Notice.who(int(f.id), seen_at, {"level": 0 if seen_at != f.tile else int(f.level), "visibility": 0.9, "unseen": true}):
		if ids.has(int(n["id"])):
			nid = int(n["id"])
			break
	if nid < 0:
		return
	asked[k] = SysUtil.now()
	var nm: String = SysUtil.folk_name(nid).get_slice(" (", 0)
	var line: String = Sexes.fill(_line("stop", nm), nid)
	SysUtil.notify(line, "warn")
	f.cancel_current("stopped by staff")
	f.clear_queue()
	JusticePlayer.ask(int(f.id), "Staff only", line,
		[{"id": "back", "label": "Turn back"}, {"id": "lie", "label": "Say you're meeting someone"}, {"id": "go", "label": "Keep going"}],
		func(ch): _answer(f, lot, nid, str(ch)), "back")

static func _answer(f, lot: String, nid: int, ch: String) -> void:
	var fid: int = int(f.id)
	var nm: String = SysUtil.folk_name(nid).get_slice(" (", 0)
	match ch:
		"back":
			SysUtil.notify(_line("turn_back", nm), "story")
			_walk_to_front(f, lot)
		"lie":
			var r: Dictionary = SkillCheck.attempt(fid, "lie", {"opponent": nid})
			if bool(r["ok"]):
				allowed["%d|%s" % [fid, lot]] = SysUtil.day()
				SysUtil.notify(_line("lie_ok", nm), "story")
			else:
				SysUtil.notify(_line("lie_fail", nm), "bad")
				_out(f, lot, nid)
		_:
			_out(f, lot, nid)

static func _walk_to_front(f, lot: String) -> void:
	var fr: Dictionary = StaffPosts.front(lot)
	if fr.is_empty():
		return
	var go: Interaction = Interaction.create_goto(f, WalkThen.near((fr["door"] as Vector2i) + (fr["inward"] as Vector2i) * 2), true, 0)
	if go != null:
		f.enqueue(go)

## Keep going past staff: a guard on duty walks them out the front door; otherwise the staff call it in.
static func _out(f, lot: String, nid: int) -> void:
	var g = StaffPosts.guard_at(lot)
	var fid: int = int(f.id)
	if g != null:
		SysUtil.notify(_line("escort", str(g.name).get_slice(" (", 0)), "bad")
		f.cancel_current("escorted out")
		f.clear_queue()
		var fr: Dictionary = StaffPosts.front(lot)
		var out: Vector2i = NeighborhoodLots.street_tile(lot) if fr.is_empty() else (fr["door"] as Vector2i) - (fr["inward"] as Vector2i) * 3
		var go: Interaction = Interaction.create_goto(f, WalkThen.near(out), true, 0)
		if go != null:
			f.enqueue(go)
		CrimePetty.commit("trespassing", fid, "venue:" + lot, {"seen": true})
		return
	SysUtil.notify(_line("call", SysUtil.folk_name(nid).get_slice(" (", 0)), "bad")
	CrimePetty.commit("trespassing", fid, "venue:" + lot, {"seen": true})
