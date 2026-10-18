class_name Neighborhood
extends RefCounted
## The neighbourhood: a map of ~11 lots (the player's home, 3 townie homes and community venues), and travel between them.
## Only ONE lot is loaded into the World at a time. Leaving a lot stores its state (World.save_dict + Economy ownership)
## in `stash`; folk who are not on the loaded lot stay in World.folk but are "off-lot": hidden (meta "offlot"/"away") and
## held in a long `sys_away` ("stay") interaction, so the SimDirector keeps ticking their needs, Careers/School keep
## dispatching them and Economy keeps paying wages. NeighborhoodService adds simple satisfaction rules for them.
##
## Public API (all static):
##   Neighborhood.start_game(template_id)            fresh game: build the home lot
##   Neighborhood.travel(folk_ids, lot_id, opts)     -> {ok, reason, minutes, lot_id, moved:[ids]}
##   Neighborhood.go_home(folk_ids = [])             everybody (or the given folk) back home
##   Neighborhood.where(folk_id) / folk_at(lot_id)   location bookkeeping
##   Neighborhood.lots() / lot(id) / is_open(id) / travel_minutes(a, b) / residents_of(lot_id)
##   Neighborhood.to_dict() / from_dict(d)           persistence (the loaded lot itself is saved by SaveLoad's "world")

const HOME := "home"
const STAY := "stay"
const TRAVEL := "travel"
const HELD_REASONS := ["work", "school", "party"]    # away reasons we never interrupt

static var current_lot: String = HOME
static var home_template: String = LotLoader.CLASSIC
static var stash: Dictionary = {}        # lot_id -> {"world": Dictionary, "owner": Dictionary, "placed": Dictionary}
static var loc: Dictionary = {}          # folk_id -> lot_id the folk is at (or travelling to)
static var pantry: int = 0               # grocery units bought at the market, delivered to the home fridge
static var visits: Dictionary = {}       # lot_id -> number of times the player went there
static var last_report: Dictionary = {}
static var meetups: Array = []           # invitations to hang out at a venue

static var _cfg_cache: Dictionary = {}

# ------------------------------------------------------------------ data
static func cfg() -> Dictionary:
	return SysUtil.table("neighborhood")

static func lots() -> Array:
	return cfg().get("lots", [])

static func lot_ids() -> Array:
	var out: Array = []
	for l in lots():
		out.append(str(l["id"]))
	return out

static func lot(lot_id: String) -> Dictionary:
	for l in lots():
		if str(l["id"]) == lot_id:
			return l
	return {}

static func starts() -> Array:
	return cfg().get("starts", [])

static func start_def(start_id: String) -> Dictionary:
	for s in starts():
		if str(s["id"]) == start_id:
			return s
	return {}

## Template id that builds this lot (home -> the chosen home template).
static func template_of(lot_id: String) -> String:
	if lot_id == HOME:
		return home_template
	return str(lot(lot_id).get("template", ""))

static func label_of(lot_id: String) -> String:
	return str(lot(lot_id).get("label", lot_id))

static func venue_type(lot_id: String = "") -> String:
	return Venues.type_of_lot(current_lot if lot_id == "" else lot_id)

static func is_home(lot_id: String = "") -> bool:
	return (current_lot if lot_id == "" else lot_id) == HOME

static func is_open(lot_id: String) -> bool:
	return Venues.is_open(lot_id)

static func pos_of(lot_id: String) -> Vector2:
	var p: Array = lot(lot_id).get("pos", [0, 0])
	return Vector2(float(p[0]), float(p[1]))

static func distance(a: String, b: String) -> int:
	if a == b:
		return 0
	var pa := pos_of(a)
	var pb := pos_of(b)
	return int(absf(pa.x - pb.x) + absf(pa.y - pb.y))

static func travel_minutes(a: String, b: String) -> int:
	if a == b:
		return 0
	var t: Dictionary = cfg().get("travel", {})
	var m: int = int(t.get("base_min", 5)) + int(t.get("per_block_min", 4)) * distance(a, b)
	return clampi(m, int(t.get("base_min", 5)), int(t.get("max_min", 40)))

## Townies living at a townie-home lot (Story townies are spread over the three homes by their `lot` number).
static func residents_of(lot_id: String) -> Array:
	var homes: Array = []
	for l in lots():
		if str(l.get("type", "")) == "townie_home":
			homes.append(str(l["id"]))
	var idx: int = homes.find(lot_id)
	var out: Array = []
	if idx < 0:
		return out
	for t in Story.alive_townies():
		if (int(t.get("lot", 1)) - 1) % homes.size() == idx and Story.stage_of(t) != "baby":
			out.append(t)
	return out

static func home_of_townie(townie_id: int) -> String:
	for l in lots():
		if str(l.get("type", "")) == "townie_home":
			for t in residents_of(str(l["id"])):
				if int(t["id"]) == townie_id:
					return str(l["id"])
	return ""

# ------------------------------------------------------------------ state
static func reset() -> void:
	current_lot = HOME
	home_template = LotLoader.CLASSIC
	stash.clear()
	loc.clear()
	pantry = 0
	visits.clear()
	meetups.clear()
	last_report = {}
	Crowd.reset()

static func where(folk_id: int) -> String:
	return str(loc.get(folk_id, current_lot))

## Resident folk ids at a lot (including folk in transit to it).
static func folk_at(lot_id: String) -> Array:
	var out: Array = []
	for f in SysUtil.residents():
		if where(int(f.id)) == lot_id:
			out.append(int(f.id))
	return out

static func traveling(folk_id: int) -> bool:
	return str(Away.info(folk_id).get("reason", "")) == TRAVEL or str((Away.pending.get(folk_id, {}) as Dictionary).get("reason", "")) == TRAVEL

static func is_stored(f) -> bool:
	return f != null and f.has_meta("offlot")

# ------------------------------------------------------------------ new game
## Build the home lot from a template (or "classic") and forget everything about other lots.
static func start_game(template_id: String = LotLoader.CLASSIC) -> bool:
	reset()
	home_template = template_id
	NeighborhoodContent.install()
	var ok: bool = LotLoader.apply(template_id)
	last_report = LotLoader.report.duplicate(true)
	current_lot = HOME
	return ok

## Call after SystemsManager.new_game (which resets this class): remember the chosen home, scale the starting funds.
## `funds` >= 0 overrides the start's own number (the new-game flow passes scenario funds x difficulty).
static func finish_new_game(start_id: String, funds: int = -1) -> void:
	var sd: Dictionary = start_def(start_id)
	home_template = str(sd.get("template", LotLoader.CLASSIC))
	if funds < 0 and sd.has("funds"):
		funds = int(sd["funds"])
	if funds >= 0:
		var hid: int = Economy.primary_household()
		WorldIface.coins[hid] = 0
		Economy.deposit(hid, funds, "starting funds")

# ------------------------------------------------------------------ travel
## Which of these folk can actually be moved right now (residents that are not at work / school / a party).
static func movable(folk_ids: Array) -> Array:
	var out: Array = []
	for id in folk_ids:
		var f = SysUtil.folk(int(id))
		if f == null or not SysUtil.is_resident(f):
			continue
		var rs: String = str(Away.info(int(id)).get("reason", ""))
		if rs == "" and Away.pending.has(int(id)):
			rs = str((Away.pending[int(id)] as Dictionary).get("reason", ""))
		if rs in HELD_REASONS:
			continue
		out.append(int(id))
	return out

static func can_travel(folk_ids: Array, lot_id: String) -> Dictionary:
	if lot(lot_id).is_empty():
		return {"ok": false, "reason": "Unknown place."}
	var ids: Array = movable(folk_ids)
	if ids.is_empty():
		return {"ok": false, "reason": "Nobody free to go (at work, school or a party)."}
	var all_there := true
	for id in ids:
		if where(int(id)) != lot_id or traveling(int(id)) or is_stored(SysUtil.folk(int(id))):
			all_there = false
	if all_there and lot_id == current_lot:
		return {"ok": false, "reason": "Already there."}
	if lot_id != HOME:
		var chk := Venues.check_entry(lot_id, ids)
		if not bool(chk["ok"]):
			return {"ok": false, "reason": str(chk["reason"])}
	return {"ok": true, "reason": ""}

## Move `folk_ids` to `lot_id`. The target lot gets loaded into the World (the previous one is stored); folk not
## travelling stay where they are as off-lot folk. Movers are away for the travel time, then appear at the lot entry.
static func travel(folk_ids: Array, lot_id: String, opts: Dictionary = {}) -> Dictionary:
	var chk := can_travel(folk_ids, lot_id)
	if not bool(chk["ok"]):
		if not bool(opts.get("quiet", false)):
			SysUtil.notify(str(chk["reason"]), "warn")
		return {"ok": false, "reason": chk["reason"], "minutes": 0, "lot_id": lot_id, "moved": []}
	var ids: Array = movable(folk_ids)
	var from_lot := current_lot
	if lot_id != HOME and not bool(opts.get("free", false)):
		if not Venues.charge_entry(lot_id, ids):
			return {"ok": false, "reason": "Could not pay the entry fee.", "minutes": 0, "lot_id": lot_id, "moved": []}
	var minutes: int = 0
	var per: Dictionary = {}
	for id in ids:
		var m: int = travel_minutes(where(int(id)), lot_id)
		if bool(opts.get("instant", false)):
			m = 0
		per[id] = m
		minutes = maxi(minutes, m)
	for id in ids:
		var mf = SysUtil.folk(int(id))
		NeighborhoodLots._detach_away(mf)
		if mf.current != null and mf.current.def_id != Away.IID:
			mf.cancel_current("travel")
		mf.clear_queue()
	if lot_id != current_lot:
		NeighborhoodLots._leave_current_lot(ids)
		NeighborhoodLots._load_lot(lot_id)
	var entries: Array = _entry_tiles()
	var i := 0
	for id in ids:
		var f = SysUtil.folk(int(id))
		loc[int(id)] = lot_id
		f.tile = entries[i % entries.size()]
		i += 1
		NeighborhoodLots._clear_stay_marks(f)
		var m2: int = int(per[id])
		if m2 >= 2:
			Away.send(f, float(m2), TRAVEL, {"label": "Travelling to %s" % label_of(lot_id), "lot_id": lot_id, "from": from_lot})
			f.set_meta("away", TRAVEL)
		_refresh_view(int(id))
	# folk who were already stored here come back out
	for f2 in SysUtil.residents():
		if where(int(f2.id)) == lot_id and f2.has_meta("offlot") and not ids.has(int(f2.id)):
			NeighborhoodLots.appear(f2)
	visits[lot_id] = int(visits.get(lot_id, 0)) + 1
	if lot_id == HOME:
		apply_pantry()
	var names: Array = []
	for id in ids:
		names.append(SysUtil.folk_name(int(id)))
	var note: String = "%s %s %s (%d min)." % [", ".join(names), "head home" if lot_id == HOME else "head to", "" if lot_id == HOME else label_of(lot_id), minutes]
	SysUtil.notify(note.strip_edges(), "travel")
	SysUtil.game_event("lot_changed", {"from": from_lot, "to": lot_id, "folk_ids": ids.duplicate(), "minutes": minutes, "entry": entries[0]})
	Crowd.on_lot_loaded(lot_id)
	_focus_camera(Vector2i(WorldIface.world().width / 2, WorldIface.world().height / 2 - 2))
	return {"ok": true, "reason": "", "minutes": minutes, "lot_id": lot_id, "moved": ids}

static func go_home(folk_ids: Array = []) -> Dictionary:
	var ids: Array = folk_ids
	if ids.is_empty():
		for f in SysUtil.residents():
			ids.append(int(f.id))
	return travel(ids, HOME)

static func _entry_tiles() -> Array:
	var w = WorldIface.world()
	var out: Array = []
	if w != null and "starter_spawn_tiles" in w:
		for t in w.starter_spawn_tiles:
			out.append(t)
	if out.is_empty():
		out.append(Vector2i(w.width / 2, w.height - 3) if w != null else Vector2i(15, 20))
	return out

static func entry_tile() -> Vector2i:
	return _entry_tiles()[0]

static func _focus_camera(t: Vector2i) -> void:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var lv = (ml as SceneTree).get_first_node_in_group("lot_view")      # no LotView reference: keeps this script headless-safe
		if lv != null and lv.has_method("focus_tile"):
			lv.call("focus_tile", t)

static func _refresh_view(fid: int) -> void:
	var ev = SimEnv.events()
	ev.emit_signal("folk_removed", fid)
	ev.emit_signal("folk_added", fid)

# ------------------------------------------------------------------ pantry (market -> home fridge)
static func add_pantry(units: int) -> void:
	pantry += units

static func apply_pantry() -> int:
	if pantry <= 0 or current_lot != HOME:
		return 0
	var cap: int = int(cfg().get("pantry", {}).get("fridge_max", 10))
	var added := 0
	for o in WorldIface.world().objects_of_def("fridge"):
		var cur: int = int(float(WorldIface.state_get(o, "stock", 0.0)))
		var add: int = mini(pantry - added, maxi(cap - cur, 0))
		if add > 0:
			WorldIface.world().add_object_state(o.id, "stock", float(add))
			added += add
	if added > 0:
		pantry -= added
		SysUtil.notify("Groceries from the market stocked the fridge (+%d)." % added, "good")
	return added

# ------------------------------------------------------------------ persistence
static func to_dict() -> Dictionary:
	var st: Dictionary = {}
	for k in stash:
		var s: Dictionary = stash[k]
		st[k] = {"world": s["world"], "owner": SysUtil.str_keys(s["owner"]), "placed": SysUtil.str_keys(s["placed"])}
	return {"current": current_lot, "home_template": home_template, "stash": st, "loc": SysUtil.str_keys(loc), "pantry": pantry,
		"visits": visits.duplicate(), "meetups": meetups.duplicate(true), "npc_ids": Crowd.npc_ids(), "version": 1}

static func from_dict(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		return
	current_lot = str(d.get("current", HOME))
	home_template = str(d.get("home_template", LotLoader.CLASSIC))
	for k in (d.get("stash", {}) as Dictionary):
		var s: Dictionary = d["stash"][k]
		stash[str(k)] = {"world": s["world"], "owner": SysUtil.int_keys(s.get("owner", {})), "placed": SysUtil.int_keys(s.get("placed", {}))}
	var lc: Dictionary = SysUtil.int_keys(d.get("loc", {}))
	for k2 in lc:
		loc[int(k2)] = str(lc[k2])
	pantry = int(d.get("pantry", 0))
	visits = (d.get("visits", {}) as Dictionary).duplicate()
	meetups = (d.get("meetups", []) as Array).duplicate(true)
	# crowd / staff NPCs are not restored: remove the ones SaveLoad re-created, they respawn from the venue rules
	for nid in d.get("npc_ids", []):
		if SysUtil.folk(int(nid)) != null:
			SysUtil.world_remove_folk(int(nid))
	for f in SysUtil.residents():
		var reason: String = str(Away.info(int(f.id)).get("reason", ""))
		if reason == STAY:
			f.set_meta("offlot", str(loc.get(int(f.id), current_lot)))
	Crowd.on_lot_loaded(current_lot)
