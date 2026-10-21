class_name AutoFurnish
extends RefCounted
## "Furnish for me when I am away" (task 32f), the furniture twin of bill autopay (Economy.autopay_for). A household with a player but nobody giving
## orders for `auto_furnish.idle_days` days, whose home is still bare (HomeBare.factor >= min_bare), buys the basics from its own coins through
## Economy (a bed per person, toilet, fridge, shower, stove, a seat per person: the same list as the Getting Started tips, StartHome.basics) and
## puts them in the rooms of the home. One plain toast ("The Fernwoods bought some furniture"). Setting `mode`: auto (default) = only a household
## whose player has never given an order (an unplayed game / an absent co-op guest), on = also when a household that was played is away, off = never.
## State (saved in the economy block): the day of each household's last player order, the day it last furnished. Data: data/start_home.json
## `auto_furnish` and per basic `buy` (the cheap def to buy) and `room` (smallest | second | largest).

static var mode: String = "auto"             # the player's choice (GameSettings "auto_furnish"): auto | on | off
static var last_order: Dictionary = {}       # household id -> day of the last player order
static var done: Dictionary = {}             # household id -> day it last bought furniture for itself


static func reset() -> void:
	mode = "auto"
	last_order.clear()
	done.clear()


static func cfg() -> Dictionary:
	return StartHome.cfg().get("auto_furnish", {})


## Commands.run calls this for every order a player gives (any action).
static func note_order(player_id: int) -> void:
	var hid: int = Players.household_of(player_id)
	if hid > 0:
		last_order[hid] = SysUtil.day()


## Households the rule looks at: the players' own (or the primary one while the players table is empty).
static func households() -> Array:
	var out: Array = []
	for pid in Players.ids():
		var hid: int = Players.household_of(int(pid))
		if hid > 0 and not out.has(hid):
			out.append(hid)
	if out.is_empty():
		out.append(Economy.primary_household())
	out.sort()
	return out


## Whole days nobody has given an order for this household (the game starts on day 1).
static func idle_days(hid: int, day: int) -> int:
	return day - int(last_order.get(hid, 1))


## Would the household furnish itself today? (not whether it can afford to)
static func wanted(hid: int, day: int) -> bool:
	var c: Dictionary = cfg()
	if (SoloHome.active and not Players.ids().is_empty()) or c.is_empty() or mode == "off" or idle_days(hid, day) < int(c.get("idle_days", 2)):          # solo: the player buys their own things; a home nobody plays replaces what burnt or was taken
		return false
	if mode == "auto" and last_order.has(hid):
		return false                      # a played household keeps its furniture to the player unless they asked otherwise
	if int(done.get(hid, -99)) == day:
		return false
	var unplayed_solo: bool = SoloHome.active and Players.ids().is_empty()          # a missing toilet or fridge is enough: it burnt or was taken
	return (unplayed_solo or HomeBare.factor_of(hid) >= float(c.get("min_bare", 0.4))) and not StartHome.next_basic(hid).is_empty()


static func on_day(day: int) -> void:
	for hid in households():
		if wanted(int(hid), day):
			furnish(int(hid), day)


# ------------------------------------------------------------------ buying
## Buy what the household lacks, in the order of the basics, while it can pay and keep `reserve` coins. Returns the number of things bought.
static func furnish(hid: int, day: int) -> int:
	var w = WorldIface.world()
	if w == null or not w.has_method("place_object") or not w.has_method("can_place"):
		return 0
	var rc: Rect2i = NeighborhoodLots.rect_of(PlayerLots.home_of_household(hid))
	if rc.size.x <= 0:
		return 0
	var rooms: Array = _rooms(w, rc)
	if rooms.is_empty():
		return 0
	var reserve: int = int(cfg().get("reserve", 100))
	var placed: Array = []
	var bought: int = 0
	for b in StartHome.cfg().get("basics", []):
		var def_id: String = str(b.get("buy", ""))
		if def_id == "":
			continue
		var need: int = (StartHome._residents(hid) if bool(b.get("per_folk", false)) else 1) - StartHome._count(hid, b["defs"])
		var price: int = Economy.price_of_def(def_id)
		while need > 0 and Economy.can_afford(hid, price + reserve):
			var oid: int = -1
			for room in _rooms_by_preference(rooms, str(b.get("room", "largest"))):
				oid = _place_one(w, hid, def_id, room, rc, placed)
				if oid >= 0:
					break
			if oid < 0:
				break
			Economy.claim_bought(hid, oid, def_id, price)
			placed.append(oid)
			bought += 1
			need -= 1
	done[hid] = day
	if bought > 0:
		SysUtil.notify("%s bought some furniture." % _who(hid), "info")
		SysUtil.game_event("auto_furnished", {"household_id": hid, "count": bought})
	return bought


## "The Fernwoods" (the family name of the first resident), else "The household".
static func _who(hid: int) -> String:
	for f in SysUtil.residents():
		if int(f.household_id) == hid:
			var n: String = Aging.family_name(f, -1)
			if n != "":
				return "The %s%s" % [n, "es" if n.ends_with("s") or n.ends_with("x") or n.ends_with("z") else "s"]
			break
	return "The household"


## Indoor rooms of the home lot (ground floor), smallest first: [{tiles: [Vector2i], set: {tile: true}}].
static func _rooms(w, rc: Rect2i) -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	for y in range(rc.position.y, rc.end.y):
		for x in range(rc.position.x, rc.end.x):
			var t := Vector2i(x, y)
			var info: Dictionary = w.rooms.room_info(t)
			if info.is_empty() or bool(info.get("outdoor", true)) or seen.has(int(info["id"])):
				continue
			seen[int(info["id"])] = true
			var tiles: Array = w.rooms.room_tiles(t)
			var set: Dictionary = {}
			for q in tiles:
				set[q] = true
			out.append({"tiles": tiles, "set": set})
	out.sort_custom(func(a, b): return (a["tiles"] as Array).size() < (b["tiles"] as Array).size())
	return out


## The room the basic belongs in first, then every other room (a bathroom too small for the shower sends it elsewhere).
static func _rooms_by_preference(rooms: Array, which: String) -> Array:
	var first: Dictionary = rooms[rooms.size() - 1]
	if which == "smallest":
		first = rooms[0]
	elif which == "second" and rooms.size() >= 3:
		first = rooms[1]
	var out: Array = [first]
	for r in rooms:
		if not is_same(r, first):
			out.append(r)
	return out


## Try the room's wall-hugging spots, best first; keep the first one that leaves everything reachable. Returns the object id or -1.
static func _place_one(w, hid: int, def_id: String, room: Dictionary, rc: Rect2i, placed: Array) -> int:
	var d: Dictionary = w.get_def(def_id)
	var doors: Array = []
	for o in w.all_objects():
		if rc.has_point(o.tile) and o.has_tag("door"):
			doors.append(o.tile)
	var cands: Array = []
	for t in room["tiles"]:
		for rot in 4:
			var fp: Array = w.WorldObjectScript.footprint_of(d, t, rot)
			var ok := true
			var wall := 0
			for q in fp:
				if not room["set"].has(q):
					ok = false
					break
				for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nb: Vector2i = q + dd
					if not fp.has(nb) and (not room["set"].has(nb) or not w.edge_open(q, nb)):
						wall += 1
			if not ok or not w.can_place(def_id, t, rot):
				continue
			var near_door := false
			for dt in doors:
				for q in fp:
					if maxi(absi(q.x - dt.x), absi(q.y - dt.y)) <= 1:
						near_door = true
			if near_door:
				continue
			cands.append([-wall, t.y, t.x, rot])
	cands.sort()
	var from: Vector2i = _anchor(hid, rc)
	var tries: int = 0
	for c in cands:
		tries += 1
		if tries > 40:
			break
		var id: int = int(w.place_object(def_id, Vector2i(c[2], c[1]), int(c[3])))
		if id < 0:
			continue
		if _all_reachable(w, from, placed + [id]):
			return id
		w.remove_object(id)
	return -1


## Where the household walks from: a resident of it standing on the lot, else the lot's entry tile.
static func _anchor(hid: int, rc: Rect2i) -> Vector2i:
	for f in SysUtil.residents():
		if int(f.household_id) == hid and rc.has_point(f.tile):
			return f.tile
	return NeighborhoodLots.entry_tile(PlayerLots.home_of_household(hid))


## Can `from` still walk up to every object in `ids` (a free tile beside it)?
static func _all_reachable(w, from: Vector2i, ids: Array) -> bool:
	for id in ids:
		var o = w.get_object(int(id))
		if o == null:
			continue
		var fp: Array = o.footprint()
		var ok := false
		for q in fp:
			for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nb: Vector2i = q + dd
				if not fp.has(nb) and w.is_walkable(nb) and WorldIface.path_length(from, nb) >= 0:
					ok = true
		if not ok:
			return false
	return true


# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	if last_order.is_empty() and done.is_empty():
		return {}
	return {"last_order": SysUtil.str_keys(last_order), "done": SysUtil.str_keys(done)}


static func from_dict(d: Dictionary) -> void:
	last_order = SysUtil.int_keys((d.get("last_order", {}) as Dictionary).duplicate())
	done = SysUtil.int_keys((d.get("done", {}) as Dictionary).duplicate())
