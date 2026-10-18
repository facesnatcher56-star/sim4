class_name DisasterBig
extends RefCounted
## The big three: tornado (siren, then impact), flood (water, then mould) and earthquake (no warning), plus the shared
## "impact" that strikes the home lot's objects / structure / people and files the insurance claim (also used by hail and wildfire).

# ------------------------------------------------------------------ shared impact
## Apply `kind` at `power` to household `hid`. Returns {text, kind, loss, paid, dead:int, injured:int}.
static func impact(hid: int, kind: String, power: int, house: String = "Your home") -> Dictionary:
	var ep: int = DisasterDamage.effective_power(hid, kind, power)
	if ep <= 0:
		return {"text": "Your preparations paid off: %s came through the %s untouched." % [house.to_lower(), _noun(kind)], "kind": "good", "loss": 0, "paid": 0, "dead": 0, "injured": 0}
	var hit: Dictionary = DisasterDamage.strike(hid, kind, ep)
	var cost: int = DisasterDamage.structure(hid, kind, ep)
	var people: Dictionary = DisasterDamage.hurt_people(hid, kind, ep)
	var loss: int = int(hit["value"]) + cost
	var paid: int = DisasterDamage.claim(hid, loss)
	DisasterAftermath.sync_markers(hid)
	var texts: Array = DisasterState.cfg("texts").get(kind, [])
	var text: String = str(texts[clampi(ep - 1, 0, texts.size() - 1)]).replace("{house}", house) if not texts.is_empty() else ""
	var gone: String = DisasterDamage.list_text(hit["destroyed"])
	var broken: String = DisasterDamage.list_text(hit["broken"])
	if gone != "":
		text += " Lost: %s." % gone
	if broken != "":
		text += " Broken: %s (can be repaired)." % broken
	if int(hit["crops"]) > 0:
		text += " The crops are ruined."
	var dead: Array = people["dead"]
	var injured: Array = people["injured"]
	if not dead.is_empty():
		text += " %s did not survive." % " and ".join(dead)
	if not injured.is_empty():
		text += " %s was hurt." % " and ".join(injured) if injured.size() == 1 else " %s were hurt." % " and ".join(injured)
	if ep < power:
		text += " Your preparations softened the blow."
	if cost > 0:
		text += " Repairs: about %d coins (call the repairers at the mailbox)." % cost
	if paid > 0:
		text += " Insurance paid %d coins." % paid
	DisasterAftermath.queue_visit(hid, kind, loss, dead.size())
	return {"text": text.strip_edges(), "kind": "bad" if (not dead.is_empty() or ep >= 3) else "warn", "loss": loss, "paid": paid, "dead": dead.size(), "injured": injured.size()}

static func impact_text(hid: int, ctx: Dictionary, kind: String, power: int) -> Dictionary:
	var r: Dictionary = impact(hid, kind, power, ctx["subject"].house_name())
	return {"text": r["text"], "kind": r["kind"]}

static func _noun(kind: String) -> String:
	return {"quake": "earthquake", "hail": "hailstorm", "flood": "flood", "tornado": "tornado", "wildfire": "wildfire"}.get(kind, "storm")

# ------------------------------------------------------------------ tornado
static func tornado(ctx: Dictionary, power: int) -> Dictionary:
	var c: Dictionary = DisasterState.cfg("tornado")
	var lead: int = int(c.get("siren_min", 6))
	var siren: bool = lead > 0 and (not bool(ctx.get("forced", false)) or DisasterState.siren_when_forced)
	var rec: Dictionary = DisasterState.begin("tornado", (lead if siren else 0) + int(c.get("view_min", 30)), power, "A tornado has touched down in town!", 4)
	if bool(ctx.get("statistical", false)):
		return DisasterFar.hit(ctx, "tornado", power)
	var hid: int = int(ctx["household_id"])
	if not SysUtil.has_int(rec["hids"], hid):
		(rec["hids"] as Array).append(hid)
	(rec["data"] as Dictionary)["p%d" % hid] = power
	if not siren:
		SysUtil.game_event("disaster", {"kind": "tornado", "phase": "impact", "minutes": int(c.get("view_min", 30)), "folk_id": -1})
		return impact_text(hid, ctx, "tornado", power)
	rec["phase"] = "siren"
	rec["due"] = SysUtil.now() + lead
	DisasterAftermath.send_to_cover(hid)
	SysUtil.game_event("disaster", {"kind": "tornado", "phase": "siren", "minutes": lead, "folk_id": -1})
	return {"text": "The tornado siren is wailing over %s. Take cover now: the bathroom or the shelter is safest!" % ctx["subject"].house_name().to_lower(), "kind": "warn"}

## The siren window is over: the tornado arrives for every household that was warned.
static func tornado_impact(rec: Dictionary) -> void:
	rec["phase"] = "on"
	rec["due"] = -1
	SysUtil.game_event("disaster", {"kind": "tornado", "phase": "impact", "minutes": int(DisasterState.cfg("tornado").get("view_min", 30)), "folk_id": -1})
	for hid in rec["hids"]:
		var h: int = int(hid)
		var r: Dictionary = impact(h, "tornado", int((rec["data"] as Dictionary).get("p%d" % h, rec["power"])), "Your home")
		DisasterAftermath.announce(h, "tornado", str(r["text"]), 4, str(r["kind"]))
		for f in SysUtil.residents():
			if int(f.household_id) == h:
				f.remove_buff("siren_alert")

# ------------------------------------------------------------------ flood
static func flood(ctx: Dictionary, power: int) -> Dictionary:
	var rec: Dictionary = DisasterState.begin("flood", DisasterEvents._hours_range("flood"), power, "Days of heavy rain have flooded parts of town!", 3)
	if bool(ctx.get("statistical", false)):
		return DisasterFar.hit(ctx, "flood", power)
	var hid: int = int(ctx["household_id"])
	if not SysUtil.has_int(rec["hids"], hid):
		(rec["hids"] as Array).append(hid)
	return impact_text(hid, ctx, "flood", power)

## Flood over: wet floors turn to mould unless the household cleaned or repaired in time.
static func flood_end(rec: Dictionary) -> void:
	var start: float = float(DisasterState.cfg("flood").get("mould_start", 0.5))
	for hid in rec["hids"]:
		var r: Dictionary = DisasterState.lot("home:%d" % int(hid))
		if float(r["flood"]) > 0.0:
			r["mould"] = maxf(float(r["mould"]), start * float(r["flood"]) + 0.2)
			DisasterAftermath.sync_markers(int(hid))
			SysUtil.notify("The water is going down, but the damp is already creeping into the walls. Scrub the mould or call the repairers.", "warn")

# ------------------------------------------------------------------ earthquake
static func quake(ctx: Dictionary, power: int) -> Dictionary:
	DisasterState.begin("quake", int(DisasterState.cfg("quake").get("view_min", 1)), power, "The ground is shaking: an earthquake!", 4)
	if bool(ctx.get("statistical", false)):
		return DisasterFar.hit(ctx, "quake", power)
	var hid: int = int(ctx["household_id"])
	var rec: Dictionary = DisasterState.find("quake")
	if not rec.is_empty() and not SysUtil.has_int(rec["hids"], hid):
		(rec["hids"] as Array).append(hid)
	SysUtil.game_event("disaster", {"kind": "quake", "phase": "impact", "minutes": 1, "power": power, "folk_id": -1})
	return impact_text(hid, ctx, "quake", power)
