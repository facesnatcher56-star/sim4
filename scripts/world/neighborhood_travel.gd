class_name NeighborhoodTravel
extends RefCounted
## Getting residents from lot to lot on the one map. Neighborhood.travel / can_travel / movable / go_home delegate here.
##   walk (default)   each folk gets a player "go here" to the lot's entry tile and walks there on the street graph; the trip
##                    takes path length x Interaction.WALK_MIN_PER_TILE game minutes; entry rules run on arrival
##                    (NeighborhoodLots.on_minute).
##   fast (opts.fast) the old shortcut: the folk is hidden (Away "travel") for Neighborhood.travel_minutes and appears at the
##                    entry tile; entry fee / hours are checked and charged up front.
##   instant          teleports at once (tests, screenshots).
## opts: {fast, instant, free (no entry fee), quiet (no refusal toast), silent (no "head to" / "arrived" toast: residents going about their day)}.

## Which of these folk can be moved right now (residents that are not at work / school / a party).
static func movable(folk_ids: Array) -> Array:
	var out: Array = []
	for id in folk_ids:
		var f = SysUtil.folk(int(id))
		if f == null or not SysUtil.is_resident(f):
			continue
		var rs: String = str(Away.info(int(id)).get("reason", ""))
		if rs == "" and Away.pending.has(int(id)):
			rs = str((Away.pending[int(id)] as Dictionary).get("reason", ""))
		if rs in Neighborhood.HELD_REASONS:
			continue
		out.append(int(id))
	return out

static func can_travel(folk_ids: Array, lot_id: String, opts: Dictionary = {}) -> Dictionary:
	if DisasterState.travel_blocked():
		return {"ok": false, "reason": "The blizzard has closed the roads."}
	if Neighborhood.lot(lot_id).is_empty():
		return {"ok": false, "reason": "Unknown place."}
	var ids: Array = movable(folk_ids)
	if ids.is_empty():
		return {"ok": false, "reason": "Nobody free to go (at work, school or a party)."}
	var gate: String = SoloHome.travel_refusal(ids, lot_id)          # one-character play: locked out of the old home, the shelter is for people with no home
	if gate != "":
		return {"ok": false, "reason": gate}
	var all_there := true
	for id in ids:
		var f = SysUtil.folk(int(id))
		if NeighborhoodLots.lot_at(f.tile) != lot_id or Neighborhood.traveling(int(id)):
			all_there = false
	if all_there:
		return {"ok": false, "reason": "Already there."}
	var all_on_way := true
	for id3 in ids:
		if Neighborhood.heading_to(int(id3)) != lot_id:
			all_on_way = false
	if all_on_way:
		return {"ok": false, "reason": "", "silent": true}          # already walking there: no second plan, no second toast
	if Venues.type_of_lot(lot_id) == "hospital" and not bool(opts.get("free", false)) and HospitalVisits.patient_for(ids).is_empty():
		return {"ok": false, "reason": "The hospital is for patients and the people who visit them."}
	if lot_id != Neighborhood.HOME:
		var chk := Venues.check_entry(lot_id, ids)
		if not bool(chk["ok"]):
			return {"ok": false, "reason": str(chk["reason"])}
		var late: String = _closed_on_arrival(ids, lot_id, opts)
		if late != "":
			return {"ok": false, "reason": late}
	return {"ok": true, "reason": ""}

## A person's own outing (quiet / silent / auto opts: never a player order) to a place that will be shut by the time they walk there:
## nobody sets off on a long walk to a closed door. A player's order is still allowed (the menu shows when it opens).
static func _closed_on_arrival(ids: Array, lot_id: String, opts: Dictionary) -> String:
	if bool(opts.get("fast", false)) or bool(opts.get("instant", false)) or bool(opts.get("free", false)):
		return ""
	if not (bool(opts.get("quiet", false)) or bool(opts.get("silent", false)) or bool(opts.get("auto", false))):
		return ""
	var walk := 0
	for id in ids:
		walk = maxi(walk, walk_minutes(int(id), lot_id))
	if walk <= 0:
		return ""
	var arrive: int = SimEnv.now_min() + walk
	if Venues.open_for(lot_id, arrive, 10):          # still open for a while after they arrive: worth the walk
		return ""
	return "%s will be closed by the time they get there." % Neighborhood.label_of(lot_id)

## Estimated walking minutes for one folk from where it stands (-1: no way there).
static func walk_minutes(folk_id: int, lot_id: String) -> int:
	var f = SysUtil.folk(folk_id)
	if f == null:
		return -1
	var n: int = WorldIface.path_length(f.tile, NeighborhoodLots.entry_tile(lot_id))
	return -1 if n < 0 else int(ceil(float(n) * Interaction.WALK_MIN_PER_TILE))

static func travel(folk_ids: Array, lot_id: String, opts: Dictionary = {}) -> Dictionary:
	var chk := can_travel(folk_ids, lot_id, opts)
	if not bool(chk["ok"]):
		if not bool(opts.get("quiet", false)) and str(chk["reason"]) != "":
			SysUtil.notify(str(chk["reason"]), "warn")
		return {"ok": false, "reason": chk["reason"], "minutes": 0, "lot_id": lot_id, "moved": []}
	var ids: Array = movable(folk_ids)
	var spot: Vector2i = NeighborhoodLots.entry_tile(lot_id)
	var instant: bool = bool(opts.get("instant", false))
	var fast: bool = bool(opts.get("fast", false)) or instant
	var from_lot: String = Neighborhood.lot_of_folk(SysUtil.folk(int(ids[0])))
	var minutes := 0
	if fast and lot_id != Neighborhood.HOME and not bool(opts.get("free", false)):
		if not Venues.charge_entry(lot_id, ids):
			return {"ok": false, "reason": "Could not pay the entry fee.", "minutes": 0, "lot_id": lot_id, "moved": []}
	var i := 0
	var moved: Array = []
	for id in ids:
		var f = SysUtil.folk(int(id))
		NeighborhoodLots.detach_travel(f)
		var dest: Vector2i = _spread(spot, i)
		i += 1
		if f.current != null and f.current.def_id != Away.IID:
			f.cancel_current("travel")
		f.clear_queue()
		if fast:
			var m: int = 0 if instant else Neighborhood.travel_minutes(from_lot, lot_id)
			minutes = maxi(minutes, m)
			f.tile = dest
			f.level = 0
			NeighborhoodLots.mark_inside(f, lot_id)
			f.remove_meta("walk_to")
			Neighborhood.loc.erase(int(id))
			Neighborhood.visits[lot_id] = int(Neighborhood.visits.get(lot_id, 0)) + 1
			if m >= 2:
				Away.send(f, float(m), Neighborhood.TRAVEL, {"label": "Travelling to %s" % Neighborhood.label_of(lot_id), "lot_id": lot_id, "from": from_lot})
				f.set_meta("away", Neighborhood.TRAVEL)
			Neighborhood.refresh_view(int(id))
		else:
			var n: int = WorldIface.path_length(f.tile, dest)
			if n < 0:
				continue
			minutes = maxi(minutes, int(ceil(float(n) * Interaction.WALK_MIN_PER_TILE)))
			f.set_meta("walk_to", lot_id)
			if bool(opts.get("silent", false)):
				f.set_meta("silent_trip", true)
			else:
				f.remove_meta("silent_trip")
			if bool(opts.get("free", false)):
				f.set_meta("free_pass", lot_id)
			Neighborhood.loc[int(id)] = lot_id
			NeighborhoodLots.walk_to(f, dest, lot_id)
		moved.append(int(id))
	if moved.is_empty():
		return {"ok": false, "reason": "No way there.", "minutes": 0, "lot_id": lot_id, "moved": []}
	if fast and lot_id == Neighborhood.HOME:
		Neighborhood.apply_pantry()
	var names: Array = []
	for id2 in moved:
		names.append(SysUtil.folk_name(int(id2)))
	var s_: String = "s" if names.size() == 1 else ""          # "Tristan heads home", "Tristan and Mina head home"
	var verb: String = "head%s home" % s_ if lot_id == Neighborhood.HOME else "head%s to %s" % [s_, Neighborhood.label_of(lot_id)]
	var pat: Dictionary = HospitalVisits.patient_for(moved) if Venues.type_of_lot(lot_id) == "hospital" and not bool(opts.get("free", false)) else {}
	if not pat.is_empty():
		verb = "go%s to the hospital to visit %s" % ["es" if names.size() == 1 else "", str(pat["name"])]
	if not bool(opts.get("silent", false)):          # silent = an unplayed household's own outing (PlaceAuto): no toast
		SysUtil.notify("%s %s (%d min%s)." % [" and ".join(names), verb, minutes, "" if not fast else ", fast travel"], "travel")
	SysUtil.game_event("lot_changed", {"from": from_lot, "to": lot_id, "folk_ids": moved.duplicate(), "minutes": minutes, "entry": spot, "walk": not fast})
	if fast:
		Neighborhood.focus_camera(spot)
	return {"ok": true, "reason": "", "minutes": minutes, "lot_id": lot_id, "moved": moved}

static func go_home(folk_ids: Array = [], opts: Dictionary = {}) -> Dictionary:
	var ids: Array = folk_ids
	if ids.is_empty():
		for f in SysUtil.residents():
			ids.append(int(f.id))
	return travel(ids, Neighborhood.HOME, opts)

## A free standable tile near `spot` for the i-th traveller (so a group does not stack on one tile).
static func _spread(spot: Vector2i, i: int) -> Vector2i:
	if i == 0:
		return spot
	var w = WorldIface.world()
	var offs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(2, 0), Vector2i(-2, 0), Vector2i(1, 1)]
	for k in offs.size():
		var c: Vector2i = spot + (offs[(i - 1 + k) % offs.size()] as Vector2i)
		if w == null or w.is_walkable(c):
			return c
	return spot