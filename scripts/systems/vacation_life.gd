class_name VacationLife
extends RefCounted
## Life at the destination (task 22): the people who live or travel there, the weather of the place, small happenings, and what the
## activities leave behind (photos, souvenirs, spending money).
##   * NPCS: a capped roster per trip (config destination `locals`), materialised as crowd-style Folk (CrowdDrive picks their activities
##     from the zone's own objects, no full Autonomy search), respawned when a load removed them, removed when the trip ends. Romances start
##     with them (event local_romance). Cruise passengers (real townies) and crew use the same machinery (CruiseCrew).
##   * WEATHER: one roll per day from the destination's weather table; buffs for people outdoors (rain, heat, snow).
##   * EVENTS: data-driven hourly happenings (destination `events`), applied to one traveller, logged through VacationLog.
## Tier: FULL near the travellers (they are in the zone). Cadence: weather 1/day, events 1/hour, NPC upkeep 1/hour. Active set: the trips
## that are "there". Caps: config locals (<= 8), photo captions 40 per trip, roster entries only.

const LOCAL_ID_BASE := 8000
const NPC_PER_CALL := 3

static func reset() -> void:
	pass

static func to_dict() -> Dictionary:
	return {}

static func from_dict(_d: Dictionary) -> void:
	pass

static func dest_def(t: Dictionary) -> Dictionary:
	return VacationCost.dest_def(str(t["dest"]))

# ------------------------------------------------------------------ start / stop
static func start(t: Dictionary) -> void:
	var dd: Dictionary = dest_def(t)
	var r := Vacation.rng_for(t)
	var taken: Array = []
	var pool: Array = ["social", "outdoorsy", "foodie", "charmer", "romantic", "active", "easygoing", "musical", "creative", "optimist", "shy", "generous"]
	var roster: Array = []
	for i in mini(int(dd.get("locals", 4)), 8):
		var tr: Array = []
		for _k in 2:
			var tt: String = str(pool[r.randi_range(0, pool.size() - 1)])
			if not tr.has(tt):
				tr.append(tt)
		var first: String = Names.pick_first(taken, r)
		taken.append(first)
		roster.append({"id": LOCAL_ID_BASE + int(t["zone"]) * 40 + i, "name": "%s %s" % [first, Names.pick_last(r)],
			"traits": tr, "kind": "local", "townie": -1, "role": "", "tile": [], "level": 0})
	t["roster"] = roster
	roll_weather(t)
	ensure_npcs(t, 4)

static func stop(t: Dictionary) -> void:
	for f in WorldIface.all_folk().duplicate():
		if f.has_meta("trip_npc") and int(f.get_meta("trip_npc")) == int(t["id"]):
			Crowd.dismiss(f)
	forget(t)
	for fid in t["folk"]:
		var f2 = SysUtil.folk(int(fid))
		if f2 != null:
			f2.remove_buff("trip_snow")

## Drop the relationship pairs with the people who stayed behind (they are not part of the town; keeps the pair store small).
static func forget(t: Dictionary) -> void:
	var ids: Dictionary = {}
	for e in t.get("roster", []):
		if int(e.get("townie", -1)) < 0:
			ids[int(e["id"])] = true
	if ids.is_empty():
		return
	for key in RelationshipService.pairs.keys():
		var pr: Dictionary = RelationshipService.pairs[key]
		if ids.has(int(pr.get("lo", -1))) or ids.has(int(pr.get("hi", -1))):
			RelationshipService.erase_pair(key)

static func after_load(t: Dictionary) -> void:
	ensure_npcs(t, 6)

# ------------------------------------------------------------------ NPCs
static func zone_rect(t: Dictionary) -> Rect2i:
	return DestLoader.zone_rect(int(t["zone"]))

static func present_ids(t: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for f in WorldIface.all_folk():
		if f.has_meta("trip_npc") and int(f.get_meta("trip_npc")) == int(t["id"]):
			out[int(f.id)] = f
	return out

## Spawn the missing roster people (at most `limit` per call).
static func ensure_npcs(t: Dictionary, limit: int = NPC_PER_CALL) -> int:
	if int(t.get("zone", -1)) < 0:
		return 0
	var have: Dictionary = present_ids(t)
	var made: int = 0
	var r := Vacation.rng_for(t)
	for e in t.get("roster", []):
		if made >= limit:
			break
		if have.has(int(e["id"])) or bool(e.get("gone", false)):
			continue
		if int(e.get("townie", -1)) >= 0 and (SysUtil.folk(int(e["townie"])) != null or not bool(Story.townies.get(int(e["townie"]), {}).get("alive", false))):
			continue
		if spawn_npc(t, e, r) != null:
			made += 1
	return made

static func spawn_npc(t: Dictionary, e: Dictionary, r: RandomNumberGenerator):
	var rc := zone_rect(t)
	var lot: String = str(t["lot"])
	var tile: Vector2i
	var level: int = int(e.get("level", 0))
	if (e.get("tile", []) as Array).size() == 2:
		tile = Vector2i(int(e["tile"][0]), int(e["tile"][1]))
	else:
		var sp: Array = zone_spawns(t)
		tile = sp[r.randi_range(0, sp.size() - 1)]
	var keep_next: int = Folk._next_id
	var f: Folk
	var tid: int = int(e.get("townie", -1))
	if tid >= 0:
		var rec: Dictionary = Story.townies[tid]
		f = Folk.create(str(rec["name"]), (rec["traits"] as Array).duplicate(), tid)
		f.appearance = Genetics.normalize(Genetics.ensure(rec))
		f.age_stage = Story.stage_of(rec)
		f.set_meta("townie_id", tid)
	else:
		f = Folk.create(str(e["name"]), (e["traits"] as Array).duplicate(), int(e["id"]))
		f.age_stage = "adult"
		if str(e.get("outfit", "")) != "":
			var sg := RandomNumberGenerator.new()
			sg.seed = str(e["name"]).hash()
			f.appearance = FolkOutfits.for_role(str(e["outfit"]), GeneticsUnique.registry(), sg)
	Folk._next_id = keep_next
	f.household_id = -1
	f.set_meta("visitor", true)
	f.set_meta("trip_npc", int(t["id"]))
	f.set_meta("trip_zone", int(t["zone"]))
	if str(e["kind"]) == "crew":
		f.set_meta("staff", str(e["role"]))
		f.set_meta("staff_lot", lot)
	else:
		f.set_meta("crowd", lot)
		f.set_meta("arrived_min", SysUtil.now())
		f.set_meta("leave_min", int(t["return_min"]) + 1440)
		f.set_meta("next_act", SysUtil.now() + r.randi_range(1, 4))
		for n in f.needs:
			(f.needs[n] as Stat).set_value(r.randf_range(15.0, 65.0))
	if tid >= 0:
		RelationshipService.restore_folk(f)
	SysUtil.world_add_folk(f, tile)
	f.level = level
	Aging.apply_stage_buff(f)
	if str(e["kind"]) == "crew":
		for n2 in f.needs:
			(f.needs[n2] as Stat).set_value(60.0)
		var ir := Interaction.create("sys_staff", f, -1, false)
		if ir != null:
			f.enqueue(ir)
	else:
		f.idle_until_min = CrowdDrive.NEVER
	NeighborhoodLots.mark_inside(f, lot)
	return f

static func zone_spawns(t: Dictionary) -> Array:
	var rc := zone_rect(t)
	var dd: Dictionary = DestDefs.map(str(dest_def(t).get("map", t["dest"])) if str(t["dest"]) != "cruise" else "ship")
	var out: Array = []
	for s in dd.get("spawn", []):
		out.append(Vector2i(int(s[0]), int(s[1])) + rc.position)
	if out.is_empty():
		out.append(rc.position + Vector2i(15, 20))
	return out

# ------------------------------------------------------------------ weather
static func roll_weather(t: Dictionary) -> void:
	var dd: Dictionary = dest_def(t)
	var table: Dictionary = dd.get("weather", {"sunny": 1})
	var items: Array = []
	var weights: Array = []
	var keys: Array = table.keys()
	keys.sort()
	for k in keys:
		items.append(str(k))
		weights.append(float(table[k]))
	var r := Vacation.rng_for(t)
	var total: float = 0.0
	for w in weights:
		total += float(w)
	var roll: float = r.randf() * total
	var pick: String = str(items[items.size() - 1])
	for i in items.size():
		roll -= float(weights[i])
		if roll <= 0.0:
			pick = str(items[i])
			break
	var old: String = str(t.get("weather", ""))
	t["weather"] = pick
	t["weather_day"] = SysUtil.day()
	var wb: Dictionary = Vacation.cfg().get("weather_buffs", {})
	for f in VacationTrip.members(t):
		if pick == "snow":
			f.add_buff("trip_snow")
		else:
			f.remove_buff("trip_snow")
		var b: String = str(wb.get(pick, ""))
		if b != "" and is_outdoors(f):
			f.add_buff(b)
	if old != pick and old != "":
		VacationLog.note(t, "weather", "The weather at %s turned %s." % [str(t["label"]), pick], [], 1, false)

static func is_outdoors(f) -> bool:
	var w = WorldIface.world()
	return w != null and w.has_method("is_outdoor") and bool(w.is_outdoor(f.tile, int(f.level)))

# ------------------------------------------------------------------ hourly
static func on_hour(t: Dictionary) -> void:
	if int(t.get("zone", -1)) < 0:
		return
	if int(t.get("weather_day", -1)) != SysUtil.day() and SysUtil.hour_f() >= 5.0:
		roll_weather(t)
	ensure_npcs(t)
	if str(t["dest"]) != "cruise":
		_events(t)

static func _events(t: Dictionary) -> void:
	var r := Vacation.rng_for(t)
	var h: float = SysUtil.hour_f()
	var present: Array = []
	var rc := zone_rect(t)
	for f in VacationTrip.members(t):
		if rc.has_point(f.tile):
			present.append(f)
	if present.is_empty():
		return
	for ev in dest_def(t).get("events", []):
		var hrs: Array = ev.get("hours", [0, 24])
		if h < float(hrs[0]) or h >= float(hrs[1]):
			continue
		if ev.has("when_weather") and not (ev["when_weather"] as Array).has(str(t.get("weather", ""))):
			continue
		if r.randf() > float(ev.get("chance", 0.05)):
			continue
		var pool: Array = present
		if bool(ev.get("adult", false)):
			pool = present.filter(func(x): return str(x.age_stage) in ["adult", "elder", "teen"])
		if pool.is_empty():
			continue
		var f2 = pool[r.randi_range(0, pool.size() - 1)]
		apply_effects(t, f2, ev.get("effects", []))
		var text: String = str(ev.get("text", "")).replace("{name}", str(f2.name))
		if int(ev.get("notify", 0)) > 0 and text != "":
			SysUtil.notify(text, "travel")
		if int(ev.get("log", 0)) > 0:
			VacationLog.note(t, "event", text, [int(f2.id)], int(ev["log"]), false)
		if str(ev["id"]) == "local_romance":
			_romance_with_local(t, f2, r)

## Loot effects for one traveller; money losses come out of the spending money first.
static func apply_effects(t: Dictionary, f, effects: Array) -> void:
	for e in effects:
		var d: Dictionary = (e as Dictionary).duplicate()
		if d.has("coins_add") and int(d["coins_add"]) < 0:
			var loss: int = -int(d["coins_add"])
			var from_wallet: int = mini(loss, maxi(int(t["wallet"]), 0))
			t["wallet"] = int(t["wallet"]) - from_wallet
			d["coins_add"] = -(loss - from_wallet)
			if int(d["coins_add"]) == 0:
				d.erase("coins_add")
		if not d.is_empty():
			Loot.apply([d], {"folk": f})

static func _romance_with_local(t: Dictionary, f, r: RandomNumberGenerator) -> void:
	var locals: Array = []
	for npc in present_ids(t).values():
		if not npc.has_meta("staff") and int(npc.get_meta("townie_id", -1)) < 0:
			locals.append(npc)
	if locals.is_empty():
		return
	var npc2 = locals[r.randi_range(0, locals.size() - 1)]
	if not RomanceRules.allowed(int(f.id), int(npc2.id)):
		return
	RelationshipService.add_both(int(f.id), int(npc2.id), "friendship", 12.0)
	RelationshipService.add_both(int(f.id), int(npc2.id), "romance", 10.0)

# ------------------------------------------------------------------ activities
static func on_activity(t: Dictionary, ev: String, fid: int) -> void:
	var f = SysUtil.folk(fid)
	if f == null:
		return
	var k: Dictionary = VacationReturn.cfg()
	var r := Vacation.rng_for(t)
	match ev:
		"souvenir_bought":
			var cost: int = 18
			var take: int = mini(cost, maxi(int(t["wallet"]), 0))
			t["wallet"] = int(t["wallet"]) - take
			if take < cost:
				Economy.spend(int(t["hid"]), cost - take, "souvenir")
			var sid: String = str(dest_def(t).get("souvenir", "keepsake")) if str(t["dest"]) != "cruise" else "ship_in_a_bottle"
			var label: String = "%s from %s" % [sid.replace("_", " "), str(t["label"])]
			(t["souvenirs"] as Array).append({"id": "%s_%d" % [sid, (t["souvenirs"] as Array).size() + 1], "label": label})
			if (t["souvenirs"] as Array).size() > int(k.get("souvenir_cap", 24)):
				(t["souvenirs"] as Array).pop_front()
			VacationLog.note(t, "shop", "%s bought %s." % [f.name, label], [fid], 1, false)
			take_photo(t, f, "a souvenir stand")
		"bridge_toured":
			VacationLog.note(t, "tour", "%s toured the captain's bridge." % f.name, [fid], 1, false)
			take_photo(t, f, "the captain's bridge")
		_:
			t["fun"] = int(t["fun"]) + 1
			if r.randf() < float(k.get("photo_chance_per_fun", 0.18)):
				var what: String = "a lovely day"
				if not f.history.is_empty():
					what = str(SimEnv.data().interaction_def(str(f.history[f.history.size() - 1])).get("label", what)).to_lower()
				take_photo(t, f, what)

static func take_photo(t: Dictionary, f, what: String) -> void:
	var caps: Array = t.get("captions", [])
	t["photos"] = int(t["photos"]) + 1
	caps.append({"day": SysUtil.day(), "dest": str(t["dest"]), "text": "%s: %s" % [f.name, what]})
	while caps.size() > 40:
		caps.pop_front()
	t["captions"] = caps

static func photo_captions(t: Dictionary) -> Array:
	return (t.get("captions", []) as Array).duplicate(true)
