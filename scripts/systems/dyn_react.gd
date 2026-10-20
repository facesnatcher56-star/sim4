class_name DynReact
extends RefCounted
## Task 32c: visible reactions. When something happens (a fire, a siren, a storm, big news, a birthday, a guest at the door) the residents who hear of it
## look out of the window, walk to the door to watch, talk it over with someone close by, or comfort a worried housemate. Which of these a person does
## is data (data/dynamic_life.json `reactions`: chance x trait factors) and seeded (DynLife.dice), at most `max_per_event` people per event, and nobody
## who is asleep, at work, on an emergency or on the toilet is pulled away. Fire fighting and fleeing stay with Fire / FireFolk: only OTHER lots' fires
## and the town-wide events are reacted to here.

static func on_event(ev: String, payload: Dictionary) -> void:
	var spec: Variant = DynLife.cfg().get("reactions", {}).get(ev, null)
	if spec == null or not _applies(spec, payload):
		return
	var rc: Dictionary = DynLife.cfg().get("react", {})
	var cap: int = int(rc.get("max_per_event", 6))
	var now := SimEnv.now_min()
	var done := 0
	for f in _witnesses(spec, payload):
		if done >= cap:
			break
		if not DynLife.awake(f) or DynLife.busy_with_must(f) or now < int(f.cooldowns.get("dyn:react", -1)):
			continue
		if not (rc.get("stages", []) as Array).has(str(f.age_stage)):
			continue
		var idx := 0
		for resp in spec.get("responses", []):
			idx += 1
			if not _stage_ok(f, resp) or DynLife.dice(int(f.id), now, idx) >= float(resp.get("chance", 0.0)) * DynLife.trait_factor(f, resp.get("traits", {})):
				continue
			if _respond(f, resp, payload):
				f.cooldowns["dyn:react"] = now + int(rc.get("cool_min", 60))
				done += 1
				break

static func _stage_ok(f, resp: Dictionary) -> bool:
	var st: Array = resp.get("stages", [])
	return st.is_empty() or st.has(str(f.age_stage))

static func _applies(spec: Dictionary, payload: Dictionary) -> bool:
	if spec.has("phases") and not (spec["phases"] as Array).has(str(payload.get("phase", ""))):
		return false
	if spec.has("to") and not (spec["to"] as Array).has(str(payload.get("to", ""))):
		return false
	if int(payload.get("severity", 99)) < int(spec.get("min_severity", 0)):
		return false
	return true

## Residents who notice: `town` = everybody within reach tiles of the event (any distance without a tile), except those on the lot that is burning;
## `home` = residents at home; `household` = the household of the person the event is about.
static func _witnesses(spec: Dictionary, payload: Dictionary) -> Array:
	var out: Array = []
	var scope := str(spec.get("scope", "town"))
	var hh := -1
	if scope == "household":
		var s = SysUtil.folk(int(payload.get("folk_id", -1)))
		if s == null or not SysUtil.is_resident(s):
			return out
		hh = int(s.household_id)
	var tile: Variant = payload.get("tile", null)
	var burning_lot := str(payload.get("lot", ""))
	for f in DynLife.people():
		if Tiers.of(f) > Tiers.NEAR:
			continue
		match scope:
			"household":
				if int(f.household_id) != hh or not DynLife.at_home(f):
					continue
			"home":
				if not DynLife.at_home(f):
					continue
			_:
				if burning_lot != "" and Neighborhood.lot_of(f) == burning_lot:
					continue
				if tile is Array and absi(f.tile.x - int(tile[0])) + absi(f.tile.y - int(tile[1])) > int(spec.get("reach", 40)):
					continue
		out.append(f)
	return out

static func _respond(f, resp: Dictionary, payload: Dictionary) -> bool:
	match str(resp.get("do", "")):
		"look_out_window":
			f.add_buff("curious_about_noise")
			return DynLife.queue(f, "look_out_window")
		"go_watch":
			return _go_watch(f)
		"talk_over":
			var other = _near_housemate(f, false)
			return other != null and _try_social(f, resp, other)
		"comfort_worried":
			var worried = _near_housemate(f, true)
			return worried != null and _try_social(f, resp, worried)
		"wish_well":
			var bd = SysUtil.folk(int(payload.get("folk_id", -1)))
			if bd == null or int(bd.id) == int(f.id):
				return false
			return _try_social(f, resp, bd)
		"greet_guest":
			for gid in payload.get("guests", []):
				var g = SysUtil.folk(int(gid))
				if g != null and _try_social(f, resp, g):
					return true
	return false

## Walk to the door of the home and watch from there.
static func _go_watch(f) -> bool:
	var lot := PlayerLots.home_of(f)
	var w = WorldIface.world()
	if WorldIface.stub != null or w == null or not DynLife.at_home(f):
		return DynLife.queue(f, "look_out_window")
	var door: Vector2i = NeighborhoodLots.entry_tile(lot)
	var spot := door + Vector2i(0, int(DynLife.cfg().get("react", {}).get("watch_distance", 5)) * -1)
	if not w.is_outdoor(spot, 0) or WorldIface.path_length(f.tile, spot) < 0:
		spot = door
	if f.current != null:
		f.current.cancel("distracted")
	var ir := Interaction.create_goto(f, spot, false)
	if ir == null:
		return false
	f.enqueue(ir)
	DynLife.queue(f, "watch_commotion")
	return true

## The nearest other resident of the same household, awake and close by (worried = one who is upset or small).
static func _near_housemate(f, worried: bool):
	var best = null
	var best_d := 1 << 30
	for o in DynLife.people():
		if int(o.id) == int(f.id) or int(o.household_id) != int(f.household_id) or not DynLife.awake(o):
			continue
		var d: int = absi(o.tile.x - f.tile.x) + absi(o.tile.y - f.tile.y)
		if d > 30 or o.level != f.level and d > 12:
			continue
		if worried and not (str(o.mood_name) in ["anxious", "sad", "tense", "lonely"] or str(o.age_stage) in ["child", "toddler"]):
			continue
		if d < best_d:
			best_d = d
			best = o
	return best

## Start the first of the response's interactions (from a seeded start) the two may do together.
static func _try_social(f, resp: Dictionary, other) -> bool:
	var iids: Array = resp.get("iids", [])
	if iids.is_empty():
		return false
	var s := int(DynLife.dice(int(f.id), SimEnv.now_min(), 77) * iids.size())
	for k in iids.size():
		var iid := str(iids[(s + k) % iids.size()])
		if DynLife.queue(f, iid, int(other.id)):
			return true
	return false
