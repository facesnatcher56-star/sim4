class_name Vacation
extends RefCounted
## Holidays and cruises (task 22). A household books a trip (travel agency desk or any computer: interaction "Plan a Holiday"), pays travel +
## lodging + spending money, the travellers leave (hidden for the journey, Away "vacation"), ARRIVE at a holiday map that is loaded into a zone
## of the Southwoods strip (DestLoader; only that map is fully simulated while they are there; the town runs on its cheap statistical
## layer and the home lot is summarised by VacationHome), live their holiday under ordinary autonomy among local people (VacationLife) and come
## back (VacationReturn: souvenirs, photos, a glow, stories). Cruises add the ship, ports of call and left-behind rules (Cruise*).
##
## Public API (static; every player action is also a command: Vacation.command({player_id, folk_id, action, args, game_minute})):
##   Vacation.destinations() / quote(hid, dest, opts) / book(hid, dest, opts) / book_and_go(hid, dest, opts) / cancel(trip_id) / come_home(trip_id)
##   Vacation.on_trip(folk_id) / trip_of_folk / trip_of_household(hid) / household_empty(hid) / trip(id) / active_trips() / state_of(id)
##   Vacation.souvenirs_of(hid) / photos_of(hid) / history_list()
##   Vacation.rng_for(trip) / zone_in_use()
## Tier behaviour (docs/VACATION.md): the traveller and the destination zone are FULL; locals / crew are crowd-style NPCs capped per trip;
## the town is TOWN / STATISTICAL; idle cost is one empty-dictionary check per clock hook (trips are driven by absolute due minutes).

const SEED := 2210

static var trips: Dictionary = {}          # id -> trip record (JSON-safe, see VacationTrip.create)
static var next_id: int = 1
static var leave_used: Dictionary = {}     # folk id -> {year, used}
static var souvenirs: Dictionary = {}      # household id -> [{id, label, dest, day}]
static var photos: Dictionary = {}         # household id -> [{day, dest, text}]
static var history: Array = []             # finished trips (summaries)
static var rng: RandomNumberGenerator = RandomNumberGenerator.new()
static var _by_folk: Dictionary = {}       # folk id -> trip id (derived; only while they are away)
static var _rngs: Dictionary = {}

static func cfg() -> Dictionary:
	return (SysUtil.table("vacation").get("config", {}) as Dictionary)

static func reset() -> void:
	trips.clear()
	next_id = 1
	leave_used.clear()
	souvenirs.clear()
	photos.clear()
	history.clear()
	_by_folk.clear()
	_rngs.clear()
	rng = RandomNumberGenerator.new()
	rng.seed = SEED
	VacationLog.reset()
	VacationLife.reset()
	DestDefs.reset()

# ------------------------------------------------------------------ queries
static func destinations() -> Array:
	var out: Array = []
	var ds: Dictionary = SysUtil.table("vacation").get("destinations", {})
	var ids: Array = ["beach", "mountain", "city", "camping"].filter(func(x): return ds.has(x))
	for k in ds.keys():
		if not ids.has(k):
			ids.append(k)
	for id in ids:
		var d: Dictionary = ds[id]
		out.append({"id": str(id), "label": str(d.get("label", id)), "blurb": str(d.get("blurb", "")), "days": d.get("days", [2, 14]), "kind": "resort"})
	var sc: Dictionary = SysUtil.table("cruise_ship").get("ship", {})
	out.append({"id": "cruise", "label": str(sc.get("name", "Cruise")), "blurb": "Decks, dining, shows, ports of call and a captain's dinner.", "days": sc.get("lengths", [3, 14]), "kind": "cruise"})
	return out

static func trip(id: int) -> Dictionary:
	return trips.get(id, {})

static func state_of(id: int) -> String:
	return str(trips.get(id, {}).get("state", ""))

static func active_trips() -> Array:
	var out: Array = []
	var ids: Array = trips.keys()
	ids.sort()
	for id in ids:
		out.append(trips[id])
	return out

static func on_trip(folk_id: int) -> bool:
	return _by_folk.has(folk_id)

static func trip_of_folk(folk_id: int) -> Dictionary:
	return trips.get(int(_by_folk.get(folk_id, -1)), {})

static func trip_of_household(hid: int) -> Dictionary:
	for t in active_trips():
		if int(t["hid"]) == hid:
			return t
	return {}

## Every resident of the household is away on a trip (the house stands empty): burglars, plants, mail (VacationHome).
static func household_empty(hid: int) -> bool:
	if _by_folk.is_empty():
		return false
	var n: int = 0
	for f in SysUtil.residents():
		if int(f.household_id) != hid:
			continue
		n += 1
		if not _by_folk.has(int(f.id)):
			return false
	return n > 0

static func zone_in_use(i: int) -> bool:
	for t in trips.values():
		if int(t.get("zone", -1)) == i or int((t.get("cruise", {}) as Dictionary).get("port_zone", -1)) == i:
			return true
	return false

static func free_zone() -> int:
	for i in DestLoader.zone_count():
		if not zone_in_use(i):
			return i
	return -1

static func souvenirs_of(hid: int) -> Array:
	return (souvenirs.get(hid, []) as Array).duplicate(true)

static func photos_of(hid: int) -> Array:
	return (photos.get(hid, []) as Array).duplicate(true)

static func history_list() -> Array:
	return history.duplicate(true)

## Seeded random stream of a trip (state is saved with the trip).
static func rng_for(t: Dictionary) -> RandomNumberGenerator:
	var id: int = int(t["id"])
	if not _rngs.has(id):
		var r := RandomNumberGenerator.new()
		r.seed = int(t.get("seed", SEED)) + id * 7919
		if t.has("rng_state"):
			r.state = int(str(t["rng_state"]))
		_rngs[id] = r
	return _rngs[id]

# ------------------------------------------------------------------ booking
static func quote(hid: int, dest: String, opts: Dictionary = {}) -> Dictionary:
	return VacationCost.quote(hid, dest, opts)

## Book a holiday: charges the household and schedules the departure (opts.depart_min, default now + 30 min).
static func book(hid: int, dest: String, opts: Dictionary = {}) -> Dictionary:
	if not trip_of_household(hid).is_empty():
		return _refuse("The household already has a holiday planned.")
	var q: Dictionary = VacationCost.quote(hid, dest, opts)
	if not bool(q["ok"]):
		return _refuse(str(q["reason"]))
	if not Economy.spend(hid, int(q["total"]), "holiday: " + VacationCost.label_of(dest)):
		return _refuse("The household cannot pay for this holiday.")
	var t: Dictionary = VacationTrip.create(hid, dest, q, opts)
	trips[int(t["id"])] = t
	var names: Array = []
	for fid in t["folk"]:
		names.append(SysUtil.folk_name(int(fid)))
	SysUtil.notify("Booked: %s to %s for %d days (%d coins)." % [", ".join(names), VacationCost.label_of(dest), int(t["days"]), int(q["total"])], "travel")
	SysUtil.game_event("vacation_booked", {"trip": int(t["id"]), "household_id": hid, "dest": dest, "days": int(t["days"])})
	if dest == "cruise":
		Cruise.on_booked(t)
	return {"ok": true, "reason": "", "trip": int(t["id"]), "trip_id": int(t["id"]), "dest": dest, "total": int(q["total"]), "days": int(t["days"]),
		"depart_min": int(t["depart_min"]), "arrive_min": int(t["arrive_min"]), "return_min": int(t["return_min"]), "folk": t["folk"].duplicate()}

static func _refuse(why: String) -> Dictionary:
	SysUtil.notify(why, "warn")
	return {"ok": false, "reason": why, "trip": -1, "trip_id": -1}

## Test / report hook (task 22b): book and leave straight away. For "cruise" the result also tells the ship, route, ports and boarding times.
##   Vacation.book_and_go(household_id, "cruise", {length_days, cabin_class, guests: [], package, sitter, seed, who})
static func book_and_go(hid: int, dest: String, opts: Dictionary = {}) -> Dictionary:
	var o: Dictionary = opts.duplicate(true)
	if not o.has("depart_min"):
		o["depart_min"] = SysUtil.now() + 1
	if o.has("seed"):
		pass
	var res: Dictionary = book(hid, dest, o)
	if not bool(res["ok"]):
		return res
	var t: Dictionary = trips[int(res["trip"])]
	if dest == "cruise":
		res.merge(Cruise.describe(t), true)
	res["ship"] = res.get("ship", {})
	return res

static func cancel(trip_id: int, reason: String = "cancelled") -> bool:
	var t: Dictionary = trips.get(trip_id, {})
	if t.is_empty() or str(t["state"]) != "booked":
		return false
	var back: int = int(float(t["cost"]["total"]) * 0.8)
	Economy.deposit(int(t["hid"]), back, "holiday refund")
	SysUtil.notify("The holiday was %s. %d coins came back." % [reason, back], "travel")
	t["state"] = "cancelled"
	_finish(t)
	return true

## Head home early (the player's command).
static func come_home(trip_id: int) -> bool:
	var t: Dictionary = trips.get(trip_id, {})
	if t.is_empty() or str(t["state"]) != "there":
		return false
	VacationTrip.leave_destination(t, true)
	return true

static func _finish(t: Dictionary) -> void:
	for fid in t.get("folk", []):
		_by_folk.erase(int(fid))
	trips.erase(int(t["id"]))
	_rngs.erase(int(t["id"]))

# ------------------------------------------------------------------ commands (multiplayer-ready entry point)
## {player_id, folk_id, action, args, game_minute}; actions: book, book_and_go, cancel, come_home, go_ashore, board, linger. Returns the action's result.
static func command(cmd: Dictionary) -> Dictionary:
	var args: Dictionary = cmd.get("args", {})
	var f = SysUtil.folk(int(cmd.get("folk_id", -1)))
	var hid: int = int(f.household_id) if f != null else int(args.get("household_id", Economy.primary_household()))
	match str(cmd.get("action", "")):
		"book":
			return book(hid, str(args.get("dest", "")), args)
		"book_and_go":
			return book_and_go(hid, str(args.get("dest", "")), args)
		"cancel":
			return {"ok": cancel(int(args.get("trip", -1)))}
		"come_home":
			return {"ok": come_home(int(args.get("trip", -1)))}
		"go_ashore", "board", "linger":
			var t: Dictionary = trip_of_household(hid)
			return Cruise.command(t, str(cmd["action"]), args)
	return {"ok": false, "reason": "unknown action"}

# ------------------------------------------------------------------ clock hooks (SystemsManager; idle cost = an emptiness test)
static func on_minute() -> void:
	if trips.is_empty():
		return
	var now: int = SysUtil.now()
	for t in active_trips():
		VacationTrip.step(t, now)

static func on_hour() -> void:
	if trips.is_empty():
		return
	for t in active_trips():
		if str(t["state"]) == "there":
			VacationLife.on_hour(t)
			if str(t["dest"]) == "cruise":
				Cruise.on_hour(t)

static func on_day() -> void:
	if trips.is_empty():
		return
	for t in active_trips():
		if str(t["state"]) in ["outbound", "there", "inbound"]:
			VacationHome.on_day(t)

## Game events (SystemsManager routes them): activity hooks of the holiday interactions.
static func on_game_event(ev: String, payload: Dictionary) -> void:
	match ev:
		"vacation_fun", "souvenir_bought", "show_watched", "bridge_toured":
			var t: Dictionary = trip_of_folk(int(payload.get("folk_id", -1)))
			if not t.is_empty():
				VacationLife.on_activity(t, ev, int(payload["folk_id"]))
		"plan_vacation":
			SysUtil.game_event("vacation_open_booking", {"folk_id": int(payload.get("folk_id", -1))})
		"folk_removed":
			pass

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	for id in trips:
		if _rngs.has(id):
			trips[id]["rng_state"] = str((_rngs[id] as RandomNumberGenerator).state)
	var lu: Dictionary = {}
	for k in leave_used:
		lu[str(k)] = leave_used[k]
	var so: Dictionary = {}
	for h in souvenirs:
		so[str(h)] = souvenirs[h]
	var ph: Dictionary = {}
	for h2 in photos:
		ph[str(h2)] = photos[h2]
	var td: Dictionary = {}
	for id2 in trips:
		td[str(id2)] = trips[id2]
	return {"version": 1, "trips": td.duplicate(true), "next_id": next_id, "leave_used": lu, "souvenirs": so.duplicate(true), "photos": ph.duplicate(true),
		"history": history.duplicate(true), "rng_state": str(rng.state), "log": VacationLog.to_dict(), "life": VacationLife.to_dict()}

static func from_dict(d: Dictionary) -> void:
	reset()
	VacationContent.install()                    # Incidents.from_dict just reloaded the incident config (the norovirus kind lives there)
	if d.is_empty():
		return
	next_id = int(d.get("next_id", 1))
	rng.state = int(str(d.get("rng_state", rng.state)))
	for k in d.get("leave_used", {}):
		leave_used[int(k)] = (d["leave_used"][k] as Dictionary).duplicate()
	for h in d.get("souvenirs", {}):
		souvenirs[int(h)] = (d["souvenirs"][h] as Array).duplicate(true)
	for h2 in d.get("photos", {}):
		photos[int(h2)] = (d["photos"][h2] as Array).duplicate(true)
	history = (d.get("history", []) as Array).duplicate(true)
	for k2 in d.get("trips", {}):
		var t: Dictionary = (d["trips"][k2] as Dictionary).duplicate(true)
		VacationTrip.normalise(t)
		trips[int(t["id"])] = t
		if str(t["state"]) in ["outbound", "there", "inbound"]:
			for fid in t["folk"]:
				_by_folk[int(fid)] = int(t["id"])
	VacationLog.from_dict(d.get("log", {}))
	VacationLife.from_dict(d.get("life", {}))
	for t2 in active_trips():
		VacationTrip.after_load(t2)
