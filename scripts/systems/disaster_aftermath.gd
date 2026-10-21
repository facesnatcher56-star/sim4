class_name DisasterAftermath
extends RefCounted
## After the storm (task 06): take-cover orders, status markers, the cleanup / repair / insurance / scrub interactions (their
## game events land here), mould that creeps on, neighbours who visit and give gifts, and the town's shared grief.

# ------------------------------------------------------------------ warning: take cover
static func send_to_cover(hid: int) -> int:
	var all: Array = DisasterDamage.objects(hid)
	var spots: Array = LevelDisasters.cover_spots(all)          # basement fixtures, else the ground floor (never upstairs)
	var cellar: Array = LevelDisasters.basement_spot(all) if spots.is_empty() else []
	var sent: int = 0
	for f in DisasterDamage.folk_on_lot(hid):
		f.add_buff("siren_alert")
		if spots.is_empty() and not cellar.is_empty() and not LevelDisasters.in_basement(f):      # no fixture: wait in the basement
			var go := Interaction.create_goto(f, cellar[0], false, int(cellar[1]))
			if go != null:
				f.enqueue(go)
				sent += 1
			continue
		if spots.is_empty() or (f.current != null and str(f.current.def_id) == "take_cover"):
			continue
		var best = spots[0]
		for s in spots:
			if absi(s.tile.x - f.tile.x) + absi(s.tile.y - f.tile.y) < absi(best.tile.x - f.tile.x) + absi(best.tile.y - f.tile.y):
				best = s
		var ir := Interaction.create("take_cover", f, int(best.id), false)
		if ir != null:
			f.enqueue(ir)
			sent += 1
	return sent

# ------------------------------------------------------------------ status markers
## Residents carry `home_damaged` while the lot needs repairs and `mouldy_home` while there is mould.
static func sync_markers(hid: int) -> void:
	var r: Dictionary = DisasterState.lots.get("home:%d" % hid, {})
	var damaged: bool = not r.is_empty() and (int(r["cost"]) > 0 or not (r["broken"] as Array).is_empty())
	var mouldy: bool = not r.is_empty() and float(r["mould"]) >= 0.3
	for f in SysUtil.residents():
		if int(f.household_id) != hid:
			continue
		_mark(f, "home_damaged", damaged)
		_mark(f, "mouldy_home", mouldy)

static func _mark(f, buff: String, on: bool) -> void:
	if on and not f.has_buff(buff):
		f.add_buff(buff)
	elif not on and f.has_buff(buff):
		f.remove_buff(buff)

## A delayed (post-siren) result: the incident text was the warning, so toast + chronicle the outcome here.
static func announce(hid: int, kind: String, text: String, sev: int, tone: String = "warn") -> void:
	SysUtil.notify(text, tone)
	var ids: Array = []
	for f in SysUtil.residents():
		if int(f.household_id) == hid and ids.size() < 4:
			ids.append(int(f.id))
	ChronicleHook.note(kind, text, ids, "home:%d" % hid, sev, true)
	DisasterState.note_lot_event("home:%d" % hid, kind, text)

# ------------------------------------------------------------------ repairs
## What the repairers charge: the structure plus 25% of the price of every disaster-broken object.
static func repair_quote(hid: int) -> int:
	var r: Dictionary = DisasterState.lots.get("home:%d" % hid, {})
	if r.is_empty():
		return 0
	var q: int = int(r["cost"])
	for oid in r["broken"]:
		var o = WorldIface.get_object(int(oid))
		if o != null and bool(WorldIface.state_get(o, "broken", false)):
			q += int(Economy.object_price(o) * 0.25)
	return q

static func repair(hid: int) -> Dictionary:
	var q: int = repair_quote(hid)
	var key: String = "home:%d" % hid
	if q <= 0:
		return {"ok": false, "paid": 0, "text": "Nothing here needs the repairers."}
	if not Economy.spend(hid, q, "disaster repairs"):
		return {"ok": false, "paid": 0, "text": "The repairers want %d coins for this job, and the household cannot afford it yet." % q}
	var r: Dictionary = DisasterState.lot(key)
	for oid in r["broken"]:
		var o = WorldIface.get_object(int(oid))
		if o != null:
			WorldIface.state_set(o, "broken", false)
	r["broken"] = []
	r["cost"] = 0
	r["roof"] = 0.0
	r["cracks"] = 0.0
	r["flood"] = 0.0
	r["mould"] = minf(float(r["mould"]), 0.25)
	sync_markers(hid)
	return {"ok": true, "paid": q, "text": "The repairers fixed everything for %d coins." % q}

# ------------------------------------------------------------------ events from interactions
static func on_game_event(ev: String, payload: Dictionary) -> void:
	var f = SysUtil.folk(int(payload.get("folk_id", -1)))
	var hid: int = int(f.household_id) if f != null else 0
	match ev:
		"debris_cleared":
			_debris_cleared(hid, int(payload.get("object_id", -1)))
		"call_repairers":
			if hid > 0:
				var res: Dictionary = repair(hid)
				SysUtil.notify(str(res["text"]), "good" if bool(res["ok"]) else "warn")
		"change_insurance":
			if hid > 0:
				DisasterInsurance.cycle(hid)
				SysUtil.notify(DisasterInsurance.describe(hid), "info")
		"scrubbed_mould":
			if hid > 0:
				var r: Dictionary = DisasterState.lot("home:%d" % hid)
				r["mould"] = maxf(0.0, float(r["mould"]) - 0.5)
				if float(r["mould"]) < 0.1:
					r["mould"] = 0.0
					SysUtil.notify("The mould is gone and the air is fresh again.", "good")
				sync_markers(hid)
		"meteorite_found":
			_meteorite(f, int(payload.get("object_id", -1)))

static func _debris_cleared(hid: int, oid: int) -> void:
	var o = WorldIface.get_object(oid)
	if o == null or str(o.def_id) != "debris":
		return
	var w = WorldIface.world()
	if w != null and w.has_method("remove_object"):
		w.remove_object(oid)
	Economy.on_object_removed(oid)
	var r: Dictionary = DisasterState.lot("home:%d" % hid)
	r["debris"] = maxi(int(r["debris"]) - 1, 0)
	if int(r["debris"]) == 0:
		SysUtil.notify("The last of the debris is cleared away.", "good")

static func _meteorite(f, oid: int) -> void:
	var o = WorldIface.get_object(oid)
	if o == null or str(o.def_id) != "meteorite" or f == null:
		return
	var coins: int = int(DisasterState.cfg("meteor").get("find_coins", 150))
	Economy.deposit(int(f.household_id), coins, "meteorite sold to a museum")
	var w = WorldIface.world()
	if w != null and w.has_method("remove_object"):
		w.remove_object(oid)
	Economy.on_object_removed(oid)
	SysUtil.notify("A museum bought the meteorite for %d coins." % coins, "good")

# ------------------------------------------------------------------ neighbours + grief
static func queue_visit(hid: int, kind: String, loss: int, deaths: int) -> void:
	if loss <= 0 and deaths <= 0:
		return
	DisasterState.aftermath.append({"hid": hid, "day": SysUtil.day() + 1, "kind": kind, "cost": loss, "deaths": deaths})
	while DisasterState.aftermath.size() > 8:
		DisasterState.aftermath.pop_front()

static func on_day(day: int) -> void:
	var keep: Array = []
	for a in DisasterState.aftermath:
		if int(a["day"]) > day:
			keep.append(a)
		else:
			_neighbours(a)
	DisasterState.aftermath = keep
	_grief(day)
	_mould(day)

static func _neighbours(a: Dictionary) -> void:
	var c: Dictionary = DisasterState.cfg("aftermath")
	var hid: int = int(a["hid"])
	var hosts: Array = []
	for f in SysUtil.residents():
		if int(f.household_id) == hid and not SysUtil.is_away(f):
			hosts.append(f)
	if hosts.is_empty():
		return
	var host = hosts[0]
	var cands: Array = []
	for t in Story.alive_townies():
		if Story.stage_of(t) in ["baby", "toddler", "child"]:
			continue
		var known: bool = RelationshipService.knows(int(host.id), int(t["id"]))
		cands.append({"t": t, "w": 3.0 if known else 1.0})
	var names: Array = []
	var picks: int = mini(int(c.get("visitors", 2)), cands.size())
	for i in picks:
		var weights: Array = []
		for e in cands:
			weights.append(float(e["w"]))
		var idx: int = _pick(weights)
		var t: Dictionary = cands[idx]["t"]
		cands.remove_at(idx)
		names.append(str(t["name"]))
		StoryVisits.schedule_visit([int(t["id"])], int(host.id), StoryVisits.daytime(SysUtil.now() + int(c.get("visit_delay_min", 180))), int(c.get("visit_minutes", 100)), "visit")
		RelationshipService.add_both(int(host.id), int(t["id"]), "friendship", 5.0)
	if names.is_empty():
		return
	var g: Array = c.get("gift", [25, 80])
	var gift: int = Incidents.rng.randi_range(int(g[0]), int(g[1]))
	Economy.deposit(hid, gift, "neighbours' gift")
	for f2 in hosts:
		f2.add_buff("neighbours_cared")
	var msg: String = "%s came by to help after the %s. They brought food and %d coins." % [" and ".join(names), DisasterBig._noun(str(a["kind"])), gift]
	SysUtil.notify(msg, "good")
	ChronicleHook.note("aftermath", msg, [int(host.id)], "home:%d" % hid, 1, false)

static func _pick(weights: Array) -> int:
	var total: float = 0.0
	for w in weights:
		total += float(w)
	var roll: float = Incidents.rng.randf() * total
	for i in weights.size():
		roll -= float(weights[i])
		if roll <= 0.0:
			return i
	return weights.size() - 1

## Deaths from yesterday's disasters: the whole town mourns together.
static func _grief(day: int) -> void:
	var due: Array = []
	var keep: Array = []
	for d in DisasterState.deaths:
		if int(d["day"]) < day:
			due.append(d)
		else:
			keep.append(d)
	DisasterState.deaths = keep
	if due.is_empty():
		return
	var names: Array = []
	for d2 in due:
		names.append(str(d2["name"]))
	var text: String = "The town gathered to mourn %s." % ", ".join(names.slice(0, 3))
	for f in SysUtil.residents():
		f.add_buff("town_mourning")
	SysUtil.notify(text, "info")
	ChronicleHook.note("town_grief", text, [], "", 3, true)

## Mould creeps on until it is scrubbed or repaired; it can make people ill.
static func _mould(_day: int) -> void:
	var c: Dictionary = DisasterState.cfg("flood")
	for key in DisasterState.lots.keys():
		if not str(key).begins_with("home:"):
			continue
		var r: Dictionary = DisasterState.lots[key]
		if float(r["mould"]) <= 0.0:
			continue
		r["mould"] = minf(1.0, float(r["mould"]) + float(c.get("mould_per_day", 0.15)))
		var hid: int = int(str(key).get_slice(":", 1))
		sync_markers(hid)
		if float(r["mould"]) >= 0.5:
			for f in SysUtil.residents():
				if int(f.household_id) == hid and not f.has_buff("sick") and Incidents.rng.randf() < float(c.get("sick_chance_per_day", 0.25)):
					Hospital.fall_ill(f, 1, "the damp and mould")