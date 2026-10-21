class_name Notice
extends RefCounted
## Task 53 (no hints): the world tells the player through people who are really there. ONE "who notices this act right now" step for every place:
## people on the map near the act who can see it (same room, or both outdoors, in range; night outdoors halves the range) or hear it (by its noise),
## awake, and paying some attention. Each one rolls on their perception, against the actor's stealth when the actor wants to be unseen.
## Then ONE reaction picker draws what that person does from data/notice.json by their role (owner, staff, guard, passer-by), traits and whether they know the actor:
## ask, warn, shout, call it in, chase, fight back, or let it go. Lines never repeat twice in a row.
##   Notice.who(actor_id, tile, opts) -> [{id, how: saw|heard, dist}]      opts: level, visibility 0..1, noise 0..1, unseen (bool), ignore [ids]
##   Notice.react(noticer_id, actor_id, table, role) -> {id, line}         table: a key of notice.json "reactions" (car, shop, person ...)

static func cfg() -> Dictionary:
	return SysUtil.table("notice")

static func _sees(w, a: Vector2i, b: Vector2i, level: int) -> bool:
	if w == null:
		return true
	var out_a: bool = bool(w.is_outdoor(a, level))
	if out_a != bool(w.is_outdoor(b, level)):
		return false          # one inside, one out: walls and windows are not modelled as see-through
	return out_a or FireRules.same_room(a, b, level)

static func who(actor_id: int, tile: Vector2i, opts: Dictionary = {}) -> Array:
	var c: Dictionary = cfg()
	var w = WorldIface.world()
	var level: int = int(opts.get("level", 0))
	var vis: float = float(opts.get("visibility", 1.0))
	var noise: float = float(opts.get("noise", 0.0))
	var ignore: Array = opts.get("ignore", [])
	var h: float = SysUtil.hour_f()
	var night: bool = h >= 21.0 or h < 6.0
	var sight: float = float(c.get("sight", 14.0))
	var hear: float = float(c.get("hear", 16.0)) * noise
	var sneak: float = 0.0
	if bool(opts.get("unseen", false)):
		sneak = SkillCheck.level(actor_id, "stealth") / 10.0 * float(c.get("stealth_cut", 0.5))
	var out: Array = []
	for f in WorldIface.all_folk():
		var fid: int = int(f.id)
		if fid == actor_id or ignore.has(fid) or SysUtil.is_away(f) or int(f.level) != level:
			continue
		var d: float = Vector2(f.tile - tile).length()
		if d > maxf(sight, hear):
			continue
		var asleep: bool = CrimePlace.is_asleep(f)
		var per: float = 0.6 + SkillCheck.level(fid, "perception") / 10.0 * 0.6
		var busy: float = float(c.get("busy_mult", 0.6)) if f.current != null and str(f.current.def_id) not in ["go_here", "wait_here", "idle", "sys_staff"] else 1.0
		if f.has_meta("staff"):
			busy *= float(c.get("staff_watch", 1.4))          # staff at a post are watching the place: that is the job
		var range_s: float = sight * (0.5 if night and bool(w.is_outdoor(tile, level)) else 1.0) if w != null else sight
		var p_see: float = 0.0
		if not asleep and d <= range_s and _sees(w, f.tile, tile, level):
			p_see = vis * (1.0 - d / maxf(range_s, 1.0)) * per * busy * (1.0 - sneak)
		var p_hear: float = 0.0
		if hear > 0.0 and d <= hear:
			p_hear = noise * (1.0 - d / hear) * (0.3 if asleep else 1.0)
		if SysUtil.rng.randf() < p_see:
			out.append({"id": fid, "how": "saw", "dist": d})
		elif SysUtil.rng.randf() < p_hear:
			out.append({"id": fid, "how": "heard", "dist": d})
	out.sort_custom(func(a, b): return float(a["dist"]) < float(b["dist"]))
	return out

## What a person who noticed does. Weights from notice.json reactions.<table>.<role> (falls back to "passerby"), shaped by traits and acquaintance.
static func react(noticer_id: int, actor_id: int, table: String, role: String = "passerby") -> Dictionary:
	var tb: Dictionary = (cfg().get("reactions", {}) as Dictionary).get(table, {})
	var opts: Dictionary = tb.get(role, tb.get("passerby", {}))
	if opts.is_empty():
		return {"id": "ignore", "line": ""}
	var keys: Array = []
	var wts: Array = []
	var tmods: Dictionary = cfg().get("trait_mods", {})
	var knows: bool = RelationshipService.knows(noticer_id, actor_id)
	for k in opts:
		var wt: float = float((opts[k] as Dictionary).get("w", 1.0))
		for tr in tmods:
			if SocialDynamics.has_t(noticer_id, str(tr)):
				wt *= float((tmods[tr] as Dictionary).get(str(k), 1.0))
		if knows:
			wt *= float((cfg().get("knows_mods", {}) as Dictionary).get(str(k), 1.0))
		keys.append(k)
		wts.append(maxf(wt, 0.0))
	var pick: String = str(SysUtil.pick_weighted(keys, wts))
	var lines: Array = (opts[pick] as Dictionary).get("lines", [])
	var line: String = ""
	if not lines.is_empty():
		line = str(lines[PlayerPrompt._pick("notice|%s|%s|%s" % [table, role, pick], lines.size())])
		line = Sexes.fill(line.replace("{n}", SysUtil.folk_name(noticer_id)).replace("{a}", SysUtil.folk_name(actor_id)), noticer_id)
	return {"id": pick, "line": line}
