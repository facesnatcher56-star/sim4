class_name DisasterEvents
extends RefCounted
## Incident handler of task 06 ("disaster_hit", args {kind, power}) and the smaller disasters: power outage, blizzard, hailstorm,
## meteor strike, wildfire. Tornado / flood / earthquake live in DisasterBig. The handler runs once per HIT LOT: ctx.statistical
## = far lot (DisasterFar), else the FULL home lot. Town-level state (siren, headline, duration) is created once per event by
## DisasterState.begin(). Returns {text, kind} for the incident flow (toast per notify_policy + chronicle line).

static func on_hit(ctx: Dictionary, args: Dictionary) -> Dictionary:
	DisasterContent.ensure()
	var kind: String = str(args.get("kind", ""))
	var power: int = int(args.get("power", 1))
	var stat: bool = bool(ctx.get("statistical", false))
	match kind:
		"outage":
			return outage(ctx, args)
		"blizzard":
			return blizzard(ctx, power)
		"tornado":
			return DisasterBig.tornado(ctx, power)
		"flood":
			return DisasterBig.flood(ctx, power)
		"quake":
			return DisasterBig.quake(ctx, power)
		"hail":
			if not stat:
				DisasterState.begin("hail", int(DisasterState.cfg("hail").get("view_min", 20)), power, "A hailstorm is pounding the town!", 2)
			return DisasterFar.hit(ctx, "hail", power) if stat else DisasterBig.impact_text(int(ctx["household_id"]), ctx, "hail", power)
		"wildfire":
			return wildfire(ctx, power)
		"meteor":
			return meteor(ctx)
	return {}

# ------------------------------------------------------------------ power outage
static func _hours_range(key: String, field: String = "hours") -> int:
	var h: Array = DisasterState.cfg(key).get(field, [3, 8])
	return Incidents.rng.randi_range(int(h[0]), int(h[1])) * 60

const LAMPS := ["lamp", "pendant_light", "nightstand"]

static func outage(ctx: Dictionary, args: Dictionary) -> Dictionary:
	var cutoff: bool = bool(args.get("cutoff", false))
	var stat: bool = bool(ctx.get("statistical", false))
	var minutes: int = _hours_range("outage", "cutoff_hours" if cutoff else "hours")
	var headline: String = "" if cutoff else "The power has gone out across town."
	var rec: Dictionary = DisasterState.begin("outage", minutes, 1, headline, 2)
	if stat:
		return {"text": "", "kind": "info"}
	var hid: int = int(ctx["household_id"])
	var gen = _working_generator(hid)
	if gen != null and not cutoff:
		(rec["data"] as Dictionary)["gen%d" % hid] = int(gen.id)
		return {"text": "The power failed, but your generator kicked in and the lights stay on.", "kind": "good"}
	if not SysUtil.has_int(rec["hids"], hid):
		(rec["hids"] as Array).append(hid)
	power_down(hid, rec)
	var tail: String = " Lights, the TV and the heating are off until the repair crew arrives." if not cutoff else " Pay the overdue bills to get it back."
	return {"text": "%s lost power.%s" % [ctx["subject"].house_name(), tail], "kind": "warn" if not cutoff else "bad"}

static func _working_generator(hid: int):
	for o in DisasterDamage.objects(hid):
		if str(o.def_id) == "generator" and float(WorldIface.state_get(o, "fuel", 0.0)) > 0.0 and not bool(WorldIface.state_get(o, "broken", false)):
			return o
	return null

static func power_down(hid: int, rec: Dictionary) -> void:
	var off: Array = []
	for o in DisasterDamage.objects(hid):
		if LAMPS.has(str(o.def_id)) and bool(WorldIface.state_get(o, "on", false)):
			WorldIface.state_set(o, "on", false)
			off.append(int(o.id))
	(rec["data"] as Dictionary)["lamps%d" % hid] = off
	(rec["data"] as Dictionary)["since%d" % hid] = SysUtil.now()
	mark_residents(hid)

static func mark_residents(hid: int) -> void:
	for f in SysUtil.residents():
		if int(f.household_id) == hid and not f.has_buff("power_out"):
			f.add_buff("power_out")

static func power_up(hid: int, rec: Dictionary) -> void:
	for f in SysUtil.residents():
		if int(f.household_id) == hid:
			f.remove_buff("power_out")
	for oid in (rec["data"] as Dictionary).get("lamps%d" % hid, []):
		var o = WorldIface.get_object(int(oid))
		if o != null and not bool(WorldIface.state_get(o, "broken", false)):
			WorldIface.state_set(o, "on", true)

## Hourly: fridge spoilage, cold indoors, generator fuel, new arrivals get the marker.
static func tick_outage(rec: Dictionary) -> void:
	var c: Dictionary = DisasterState.cfg("outage")
	var d: Dictionary = rec["data"]
	for k in d.keys():
		if str(k).begins_with("gen"):
			var hid: int = int(str(k).substr(3))
			var g = WorldIface.get_object(int(d[k]))
			if g == null:
				continue
			WorldIface.state_add(g, "fuel", -float(c.get("fuel_per_hour", 1.0)))
			if float(WorldIface.state_get(g, "fuel", 0.0)) <= 0.0:
				d.erase(k)
				if not SysUtil.has_int(rec["hids"], hid):
					(rec["hids"] as Array).append(hid)
				power_down(hid, rec)
				SysUtil.notify("The generator ran out of fuel. The power is off again.", "warn")
	for hid2 in rec["hids"]:
		var h: int = int(hid2)
		mark_residents(h)
		var hours: float = float(SysUtil.now() - int(d.get("since%d" % h, rec["start"]))) / 60.0
		if hours >= float(c.get("spoil_after_hours", 2)):
			_spoil_fridge(h, rec, float(c.get("spoil_chance", 0.5)))
		if Weather.temperature() < float(c.get("cold_below", 8.0)):
			_chill(h)

static func _spoil_fridge(hid: int, rec: Dictionary, chance: float) -> void:
	for o in DisasterDamage.objects(hid):
		if str(o.def_id) != "fridge" or Incidents.rng.randf() >= chance:
			continue
		var lost: int = mini(Incidents.rng.randi_range(1, 3), int(float(WorldIface.state_get(o, "stock", 0.0))))
		if lost <= 0:
			continue
		WorldIface.state_add(o, "stock", -float(lost))
		WorldIface.state_add(o, "spoiled", float(lost))
		if not bool((rec["data"] as Dictionary).get("spoil_told%d" % hid, false)):
			(rec["data"] as Dictionary)["spoil_told%d" % hid] = true
			SysUtil.notify("Without power the food in the fridge is starting to spoil.", "warn")

static func _chill(hid: int) -> void:
	var warm: bool = false
	for o in DisasterDamage.objects(hid):
		if str(o.def_id) == "fireplace" and bool(WorldIface.state_get(o, "lit", false)):
			warm = true
	if warm:
		return
	for f in DisasterDamage.folk_on_lot(hid):
		if not WeatherFolk.is_outside(f) and Incidents.rng.randf() < 0.6:
			f.add_buff("cold")

# ------------------------------------------------------------------ blizzard
static func blizzard(ctx: Dictionary, power: int) -> Dictionary:
	var c: Dictionary = DisasterState.cfg("blizzard")
	var rec: Dictionary = DisasterState.begin("blizzard", _hours_range("blizzard"), power,
		"A blizzard is burying the town. The roads are closed: stay in and keep warm.", 3)
	if bool(ctx.get("statistical", false)):
		return {"text": "", "kind": "info"}
	var hid: int = int(ctx["household_id"])
	if not SysUtil.has_int(rec["hids"], hid):
		(rec["hids"] as Array).append(hid)
	var res: Dictionary = DisasterDamage.strike(hid, "blizzard", power)
	var text: String = "%s is snowed in. Heating will cost more until it clears." % ctx["subject"].house_name()
	if int(res["crops"]) > 0:
		text += " The garden is frozen solid."
	if Incidents.rng.randf() < float(c.get("outage_chance", 0.3)):
		var o: Dictionary = outage({"statistical": false, "household_id": hid, "subject": ctx["subject"]}, {})
		text += " " + str(o.get("text", ""))
	return {"text": text, "kind": "warn"}

static func tick_blizzard(rec: Dictionary) -> void:
	var c: Dictionary = DisasterState.cfg("blizzard")
	var chance: float = DisasterDamage.at(c.get("hurt_chance", [0.03]), int(rec["power"]))
	for hid in rec["hids"]:
		var h: int = int(hid)
		Economy.usage[h] = float(Economy.usage.get(h, 0.0)) + float(c.get("heat_units_per_hour", 4.0))
		for f in DisasterDamage.folk_on_lot(h):
			if WeatherFolk.is_outside(f):
				f.add_buff(str(c.get("cold_buff", "cold")))
				if Incidents.rng.randf() < chance:
					Hospital.injure(f, 1, "the cold")

# ------------------------------------------------------------------ wildfire
static func wildfire(ctx: Dictionary, power: int) -> Dictionary:
	var rec: Dictionary = DisasterState.begin("wildfire", _hours_range("wildfire"), power,
		"A wildfire is burning near the park. Smoke is drifting over town.", 4)
	if bool(ctx.get("statistical", false)):
		return DisasterFar.hit(ctx, "wildfire", power)
	var hid: int = int(ctx["household_id"])
	if not SysUtil.has_int(rec["hids"], hid):
		(rec["hids"] as Array).append(hid)
	if power >= int(DisasterState.cfg("wildfire").get("spread_power", 2)) and fire_ignite(hid, power):
		return {"text": "Sparks from the wildfire have set %s alight! Get everyone out." % ctx["subject"].house_name().to_lower(), "kind": "bad"}
	return DisasterBig.impact_text(hid, ctx, "wildfire", power)

## The target handed to Fire.ignite: an outdoor object of the lot (flammable things burn), else the first object, else a bare tile.
static func _fire_target(hid: int):
	var objs: Array = DisasterDamage.objects(hid)
	for o in objs:
		if DisasterDamage.is_outdoor(o) and not DisasterDamage.PROTECTED.has(str(o.def_id)):
			return o
	return objs[0] if not objs.is_empty() else StoryVisits.entrance()

## Hands the fire to the Fire system (task 03: Fire.ignite(target, source, opts) -> bool). Looked up by class name so this file
## still parses if Fire is ever absent; then it returns false and the caller falls back to plain damage.
static func fire_ignite(hid: int, power: int) -> bool:
	for c in ProjectSettings.get_global_class_list():
		if str(c.get("class", "")) != "Fire":
			continue
		var scr: Script = load(str(c["path"]))
		if scr != null and scr.has_method("ignite"):
			return bool(scr.call("ignite", _fire_target(hid), "wildfire", {"force": power >= 3}))
	return false

static func tick_wildfire(rec: Dictionary) -> void:
	var p: float = float(DisasterState.cfg("wildfire").get("sick_chance_per_hour", 0.004))
	for f in SysUtil.residents():
		if SysUtil.is_away(f) or Hospital.is_in(f):
			continue
		if WeatherFolk.is_outside(f):
			f.add_buff("smoky")
			if Incidents.rng.randf() < p * 4.0:
				Hospital.fall_ill(f, 1, "the smoke")
		elif Incidents.rng.randf() < p:
			Hospital.fall_ill(f, 1, "the smoke")

# ------------------------------------------------------------------ meteor (easter egg)
static func meteor(ctx: Dictionary) -> Dictionary:
	var rec: Dictionary = DisasterState.begin("meteor", 1, 1, "A bright streak tore across the sky and something crashed down in town!", 3)
	var d: Dictionary = rec["data"]
	if not d.has("target"):
		var lots: Array = IncidentChecks.lot_subjects()
		d["target"] = str(lots[Incidents.rng.randi_range(0, lots.size() - 1)].lot_key) if not lots.is_empty() else str(ctx["lot_key"])
	if str(ctx["lot_key"]) != str(d["target"]):
		return {"text": "", "kind": "info"}
	if bool(ctx.get("statistical", false)):
		return {"text": "At %s, a meteor crashed down nearby. Nobody was hurt." % ctx["subject"].house_name(), "kind": "info"}
	return meteor_home(int(ctx["household_id"]), ctx["subject"].house_name())

static func meteor_home(hid: int, house: String) -> Dictionary:
	var c: Dictionary = DisasterState.cfg("meteor")
	var outs: Array = []
	for o in DisasterDamage.objects(hid):
		if DisasterDamage.is_outdoor(o) and not DisasterDamage.PROTECTED.has(str(o.def_id)):
			outs.append(o)
	var tile: Vector2i = StoryVisits.entrance()
	if not outs.is_empty():
		tile = outs[Incidents.rng.randi_range(0, outs.size() - 1)].tile
	var lost: Array = []
	for o in DisasterDamage.objects(hid):
		if DisasterDamage.PROTECTED.has(str(o.def_id)) or not DisasterDamage.is_outdoor(o):
			continue
		if absi(o.tile.x - tile.x) + absi(o.tile.y - tile.y) <= int(c.get("object_radius", 2)):
			lost.append(str(DisasterDamage.def_of(o).get("label", o.def_id)).to_lower())
			DisasterDamage.destroy(o, hid, false)
	var hurt: Array = []
	for f in DisasterDamage.folk_on_lot(hid):
		if absi(f.tile.x - tile.x) + absi(f.tile.y - tile.y) <= int(c.get("hurt_radius", 1)):
			if Incidents.rng.randf() < float(c.get("kill_chance", 0.15)):
				Aging.kill(int(f.id), "meteor")
			else:
				Hospital.injure(f, 3, "a meteor")
			hurt.append(str(f.name))
	var w = WorldIface.world()
	if w != null and w.has_method("place_object") and (not w.has_method("can_place") or bool(w.can_place("meteorite", tile, 0))):
		var mid: int = int(w.place_object("meteorite", tile, 0))
		if mid >= 0:
			Economy.owner[mid] = hid
	var text: String = "A meteor crashed into the yard of %s, leaving a smoking rock." % house.to_lower()
	if not lost.is_empty():
		text += " It destroyed %s." % DisasterDamage.list_text(lost)
	text += " Nobody was near it." if hurt.is_empty() else " %s was caught in it." % ", ".join(hurt)
	return {"text": text, "kind": "warn"}
