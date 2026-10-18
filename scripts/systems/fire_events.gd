class_name FireEvents
extends RefCounted
## The SOURCES of fire. The incidents of data/incidents/03_fire.json roll the dice (rates, risk multipliers); their handler `fire_arm` then ARMS a
## source for the household and the fire starts at the next fitting moment: someone cooks (kitchen), a fireplace burns alone for a while,
## a device is used or repaired (electrical, botched repairs), a holiday evening (candle), at once (lightning). Forced incidents ignite at once.
## An armed source that finds no moment in time fizzles (counted as averted). Also: the summary of a finished blaze and the game-event routing.

static var armed: Array = []        # [{id, source, hid, lot, until, ignite_at, obj, culprit, unattended, warned}]
static var _aid: int = 1

static func reset() -> void:
	armed.clear()
	_aid = 1

static func to_dict() -> Dictionary:
	return {"armed": armed.duplicate(true), "aid": _aid}

static func from_dict(d: Dictionary) -> void:
	armed.clear()
	for a in d.get("armed", []):
		var c: Dictionary = (a as Dictionary).duplicate(true)
		SysUtil.ints_in(c, ["id", "hid", "until", "ignite_at", "obj", "culprit", "unattended"])
		armed.append(c)
	_aid = int(d.get("aid", 1))

# ------------------------------------------------------------------ incident handlers
## Handler `fire_arm` (args.source). Full mode only: far lots use the statistical outcomes.
static func on_arm(ctx: Dictionary, args: Dictionary) -> Dictionary:
	if bool(ctx.get("statistical", false)):
		return {}
	var source: String = str(args.get("source", "cooking"))
	var hid: int = int(ctx.get("household_id", 0))
	if hid <= 0:
		return {}
	var lot: String = _lot_of_household(hid)
	if bool(ctx.get("forced", false)) or source == "lightning":
		if not start_now(source, hid, lot, -1):
			Fire._stat("averted")
		return {}
	for a in armed:
		if int(a["hid"]) == hid and str(a["source"]) == source:
			return {}
	var days: float = float((FireRules.cfg().get("armed_days", {}) as Dictionary).get(source, 4))
	var now: int = SysUtil.now()
	var rec := {"id": _aid, "source": source, "hid": hid, "lot": lot, "until": now + int(days * 1440.0), "ignite_at": -1, "obj": -1, "culprit": -1, "unattended": 0, "warned": false}
	_aid += 1
	if source == "candle":
		var h: Array = FireRules.cfg().get("candle_hours", [18, 23])
		var at: int = (now / 1440) * 1440 + Fire.rng.randi_range(int(h[0]) * 60, int(h[1]) * 60)
		rec["ignite_at"] = at if at > now else now + 30
		rec["until"] = (now / 1440) * 1440 + 1440
	armed.append(rec)
	Fire._stat("armed")
	return {}

## Handler `fire_aftermath` (statistical): a far lot loses some of its things.
static func on_aftermath(ctx: Dictionary, args: Dictionary) -> Dictionary:
	if bool(ctx.get("statistical", false)):
		FireTown.damage(str(ctx.get("lot_key", "")), int(args.get("loss", 2)))
	return {}

static func _lot_of_household(hid: int) -> String:
	for o in Economy.objects_of(hid):
		return FireRules.lot_of(o.tile)
	return Neighborhood.HOME

# ------------------------------------------------------------------ starting a fire from a source
static func start_now(source: String, hid: int, lot: String, culprit: int, obj_id: int = -1) -> bool:
	var objs: Array = Economy.objects_of(hid)
	objs.sort_custom(func(a, b): return int(a.id) < int(b.id))
	var target = null
	match source:
		"cooking":
			target = WorldIface.get_object(obj_id) if obj_id >= 0 else _first_of(objs, ["stove", "grill"])
		"fireplace":
			var fp = _first_of(objs, ["fireplace"])
			if fp != null:
				WorldIface.state_set(fp, "lit", true)
				target = _spark_target(fp, objs)
		"electrical", "repair":
			target = WorldIface.get_object(obj_id) if obj_id >= 0 else null
			if target == null:
				var broken: Array = objs.filter(func(o): return FireRules.is_electrical(o) and bool(WorldIface.state_get(o, "broken", false)))
				var elec: Array = objs.filter(func(o): return FireRules.is_electrical(o))
				var pool: Array = broken if not broken.is_empty() else elec
				target = pool[0] if not pool.is_empty() else null
		"candle":
			var soft: Array = objs.filter(func(o): return FireRules.flammability(o) >= 0.45 and not FireRules.is_floor(o))
			target = soft[Fire.rng.randi_range(0, soft.size() - 1)] if not soft.is_empty() else null
		"lightning":
			var tall: Array = objs.filter(func(o): return FireRules.flammability(o) > 0.0 and not FireRules.is_floor(o))
			tall.sort_custom(func(a, b): return float(FireRules.obj_def(a).get("height", 1.0)) > float(FireRules.obj_def(b).get("height", 1.0)))
			target = tall[0] if not tall.is_empty() else null
	if target == null:
		return false
	return Fire.ignite(target, source, {"culprit": culprit, "force": true})

static func _first_of(objs: Array, ids: Array):
	for o in objs:
		if ids.has(str(o.def_id)):
			return o
	return null

## A spark from the fireplace lands on the most flammable thing within two tiles (a rug, a sofa), else on the fireplace itself.
static func _spark_target(fp, objs: Array):
	var best = fp
	var bf: float = -1.0
	for o in objs:
		if o == fp or (FireRules.is_floor(o) and str(o.def_id) != "rug"):
			continue
		if FireRules.dist(o.tile, fp.tile) <= 2 and FireRules.flammability(o) > bf:
			bf = FireRules.flammability(o)
			best = o
	return best

# ------------------------------------------------------------------ interaction hooks / per minute
static func on_interaction_started(folk_id: int, iid: String, target_id: int) -> void:
	if armed.is_empty():
		return
	var f = SysUtil.folk(folk_id)
	if f == null:
		return
	var now: int = SysUtil.now()
	var dur: float = float(SimEnv.data().interaction_def(iid).get("duration_min", 10.0))
	for a in armed:
		if int(a["hid"]) != int(f.household_id) or int(a["ignite_at"]) >= 0:
			continue
		if str(a["source"]) == "cooking" and (FireRules.cfg().get("cooking_iids", []) as Array).has(iid):
			var fr: Array = FireRules.cfg().get("cook_ignite_frac", [0.3, 0.75])
			a["ignite_at"] = now + maxi(int(dur * Fire.rng.randf_range(float(fr[0]), float(fr[1]))), 2)
			a["obj"] = target_id
			a["culprit"] = folk_id
		elif str(a["source"]) == "electrical":
			var o = WorldIface.get_object(target_id)
			if iid == "repair_object" or (o != null and FireRules.is_electrical(o)):
				var r: Array = FireRules.cfg().get("electrical_ignite_min", [2, 6])
				a["ignite_at"] = now + Fire.rng.randi_range(int(r[0]), int(r[1]))
				a["obj"] = target_id
				a["culprit"] = folk_id
				if iid == "repair_object":
					a["source"] = "repair"

static func step(now: int) -> void:
	for a in armed.duplicate():
		if now > int(a["until"]):
			armed.erase(a)
			Fire._stat("averted")
			continue
		if str(a["source"]) == "fireplace":
			_fireplace_watch(a)
		if int(a["ignite_at"]) < 0:
			continue
		if not bool(a["warned"]) and now >= int(a["ignite_at"]) - 2 and int(a["culprit"]) >= 0:
			a["warned"] = true
			SimEnv.emit("thought", int(a["culprit"]), "Is something burning?")
		if now >= int(a["ignite_at"]):
			armed.erase(a)
			if not start_now(str(a["source"]), int(a["hid"]), str(a["lot"]), int(a["culprit"]), int(a["obj"])):
				Fire._stat("averted")

static func _fireplace_watch(a: Dictionary) -> void:
	var lit: Array = []
	for o in Economy.objects_of(int(a["hid"])):
		if str(o.def_id) == "fireplace" and bool(WorldIface.state_get(o, "lit", false)):
			lit.append(o)
	if lit.is_empty():
		a["unattended"] = 0
		return
	var attended: bool = false
	var r: int = int(FireRules.num("fireplace_range", 6.0))
	for f in FireRules.folk_in_lot(str(a["lot"])):
		for o2 in lit:
			if FireRules.dist(f.tile, o2.tile) <= r and FireRules.same_room(f.tile, o2.tile):
				attended = true
	a["unattended"] = maxi(int(a["unattended"]) - 1, 0) if attended else int(a["unattended"]) + 1
	if int(a["unattended"]) >= int(FireRules.num("fireplace_unattended_min", 20.0)):
		a["ignite_at"] = SysUtil.now()

# ------------------------------------------------------------------ game events from interactions
static func on_game_event(ev: String, payload: Dictionary) -> void:
	match ev:
		"fire_extinguish_try":
			FireFolk.on_extinguisher_used(int(payload.get("folk_id", -1)))
		"fire_call":
			var f = SysUtil.folk(int(payload.get("folk_id", -1)))
			if f != null:
				Fire.call_brigade(FireRules.lot_of(f.tile), int(f.id))
		"fire_swept":
			var o = WorldIface.get_object(int(payload.get("object_id", -1)))
			if o != null and str(o.def_id) == "ash_pile":
				var tile: Vector2i = o.tile
				var w = WorldIface.world()
				if w != null and w.has_method("remove_object"):
					w.remove_object(int(o.id))
				Economy.on_object_removed(int(o.id))
				Fire.scorch.erase(Fire.key(tile))

# ------------------------------------------------------------------ the end of a blaze
static func summarize(b: Dictionary) -> void:
	var lot: String = str(b["lot"])
	var kind: String = str((FireRules.cfg().get("kind_labels", {}) as Dictionary).get(str(b["source"]), "fire"))
	var lost: Array = b["lost"]
	var text: String = "The %s at %s was put out." % [kind, FireRules.place_name(lot)]
	if not lost.is_empty():
		text += " Lost: %s." % _list(_counted(lost))
	var hurt: Array = []
	for id in b["hurt"]:
		var f = SysUtil.folk(int(id))
		if f != null:
			hurt.append(str(f.name))
	if not hurt.is_empty():
		text += " %s breathed in smoke and is hurt." % _list(hurt)
	var hid: int = int(b["hid"])
	if hid > 0 and int(b["loss"]) > 0:
		var cover: int = Incidents.insurance_cover(int(b["loss"]), hid)
		if cover > 0:
			Economy.deposit(hid, cover, "fire insurance")
			text += " Insurance paid %d coins." % cover
	var bad: bool = not (b["dead"] as Array).is_empty() or not hurt.is_empty()
	if FireRules.is_home(lot):
		SysUtil.notify(text, "bad" if bad else ("warn" if not lost.is_empty() else "good"))
	var subs: Array = (b["hurt"] as Array) + (b["dead"] as Array)
	var sev: int = 5 if not (b["dead"] as Array).is_empty() else (4 if bad else (3 if not lost.is_empty() else 2))
	ChronicleHook.note("fire", text, subs, ("home:%d" % hid) if hid > 0 else "", sev, true)
	SysUtil.game_event("fire_out", {"lot": lot, "source": str(b["source"]), "loss": int(b["loss"]), "spread": bool(b["spread"]), "dead": (b["dead"] as Array).size(), "folk_id": -1})

## ["Counter", "Stove", "Counter"] -> ["Counter x2", "Stove"] (order of first appearance)
static func _counted(items: Array) -> Array:
	var order: Array = []
	var n: Dictionary = {}
	for it in items:
		if not n.has(it):
			order.append(it)
		n[it] = int(n.get(it, 0)) + 1
	var out: Array = []
	for it2 in order:
		out.append(str(it2) if int(n[it2]) == 1 else "%s x%d" % [it2, n[it2]])
	return out

static func _list(items: Array) -> String:
	if items.size() == 1:
		return str(items[0])
	return "%s and %s" % [", ".join(PackedStringArray(items.slice(0, items.size() - 1))), str(items[items.size() - 1])]
