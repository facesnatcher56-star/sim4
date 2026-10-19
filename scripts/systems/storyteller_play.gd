class_name StorytellerPlay
extends RefCounted
## Plays one card of the deck for a key. Builds the context (who is it about, where, who is the other person), foreshadows medium and big bad events,
## then executes: an existing incident forced on a household / lot / townie (the incident's own handlers, toasts and chronicle), or a pure card (text + fx),
## a player CHOICE for the households people play (townies and far lots take the card's `auto` option), a city event that RIPPLES (StorytellerRipple),
## a cycle, an arc. Afterwards: heat for related cards, chains, the budget bookkeeping and the log line ("what happened and why").
## ctx is plain data so it can sit in the saved queue: {key, hid, folk_id, other, lot, zone, who, stat}.

static func lot_members(n: int) -> Array:
	if StorytellerScan.active():
		return StorytellerScan.lot_members(n)
	var out: Array = []
	for tid in Story.townies:
		var t: Dictionary = Story.townies[tid]
		if bool(t["alive"]) and int(t.get("lot", 0)) == n:
			out.append(int(tid))
	out.sort()
	return out

static func residents_of(hid: int) -> Array:
	if StorytellerScan.active():
		return StorytellerScan.residents(hid, func(): return _residents_of(hid))
	return _residents_of(hid)

static func _residents_of(hid: int) -> Array:
	var out: Array = []
	for f in WorldIface.all_folk():
		if int(f.household_id) == hid and SysUtil.is_resident(f):
			out.append(f)
	out.sort_custom(func(a, b): return a.id < b.id)
	return out

static func lots_in_zone(zone: String) -> Array:
	if StorytellerScan.active():
		return StorytellerScan.zone_lots(zone, func(): return _lots_in_zone(zone))
	return _lots_in_zone(zone)

static func _lots_in_zone(zone: String) -> Array:
	var seen: Dictionary = {}
	for tid in Story.townies:
		var t: Dictionary = Story.townies[tid]
		var n: int = int(t.get("lot", 0))
		if bool(t["alive"]) and n > 0 and CityState.zone_of_town_lot(n) == zone:
			seen[n] = true
	var out: Array = seen.keys()
	out.sort()
	return out

static func townies_in_zone(zone: String) -> Array:
	var out: Array = []
	for n in lots_in_zone(zone):
		out.append_array(lot_members(int(n)))
	return out

# ------------------------------------------------------------------ eligibility (no random numbers drawn)
static func can_play(cid: String, c: Dictionary, key: String) -> bool:
	var kind: String = StorytellerBudget.kind_of(key)
	var when: Dictionary = c.get("when", {})
	if c.has("arc"):
		return StorytellerArcs.can_start(str(c["arc"]), key)
	if c.has("cycle"):
		return StorytellerCycles.can_start(str(c["cycle"]))
	match kind:
		"home":
			return _can_home(c, when, StorytellerBudget.id_of(key))
		"lot":
			return _can_lot(c, StorytellerBudget.id_of(key))
		"district":
			return _can_district(c, StorytellerBudget.zone_of_key(key))
	return true

static func _adults(f_list: Array) -> Array:
	return f_list.filter(func(f): return str(f.age_stage) in ["adult", "elder"])

static func _can_home(c: Dictionary, when: Dictionary, hid: int) -> bool:
	var res: Array = residents_of(hid)
	if res.is_empty():
		return false
	var adults: Array = _adults(res)
	if bool(when.get("adult", false)) and adults.is_empty():
		return false
	if bool(when.get("job", false)) and not adults.any(func(f): return Careers.has_job(int(f.id))):
		return false
	if bool(when.get("nojob", false)) and not adults.any(func(f): return not Careers.has_job(int(f.id))):
		return false
	if bool(when.get("pets", false)) and not Storyteller.pets_exist(hid):
		return false
	if when.has("tier") and StorytellerBudget.tier_of("h%d" % hid) != str(when["tier"]):
		return false
	if when.has("coins_min") and Economy.balance(hid) < int(when["coins_min"]):
		return false
	if when.has("coins_max") and Economy.balance(hid) > int(when["coins_max"]):
		return false
	if when.has("min_day") and SysUtil.day() < int(when["min_day"]):
		return false
	if c.has("incident"):
		return not _incident_subjects(c, "h%d" % hid, true).is_empty()
	return true

static func _can_lot(c: Dictionary, n: int) -> bool:
	if lot_members(n).is_empty():
		return false
	if c.has("incident"):
		return bool(c.get("lot", false)) and not _incident_subjects(c, "l%d" % n, true).is_empty()
	return c.has("lot_text")

static func _can_district(c: Dictionary, zone: String) -> bool:
	if c.has("incident"):
		return not _incident_subjects(c, "d" + zone, true).is_empty()
	var fx: Array = c.get("fx", [])
	for e in fx:
		if (e as Dictionary).has("other_coins") or (e as Dictionary).has("other_friend") or (e as Dictionary).has("lay_off"):
			return not townies_in_zone(zone).is_empty()
	return true

## Subjects (IncidentSubject) an incident card can play on, in a stable order. `first_only` stops at the first one that qualifies (eligibility only asks
## whether there is any; the subjects are built one at a time, so a card that fits the first person does not test the rest of the district).
static func _incident_subjects(c: Dictionary, key: String, first_only: bool = false) -> Array:
	var def: Dictionary = IncidentDefs.get_def(str(c.get("incident", "")))
	if def.is_empty():
		return []
	var out: Array = []
	var ids: Array = []              # what to build a subject from, all of one `make` kind
	var make: String = ""
	var kind: String = StorytellerBudget.kind_of(key)
	var target: String = str(c.get("target", "lot"))
	match kind:
		"home":
			var hid: int = StorytellerBudget.id_of(key)
			if target == "lot":
				ids = [hid]
				make = "household"
			else:
				ids = residents_of(hid)
				make = "folk"
		"lot":
			var n: int = StorytellerBudget.id_of(key)
			if target == "lot":
				ids = [n]
				make = "town_lot"
			else:
				ids = lot_members(n)
				make = "townie"
		"district":
			var zone: String = StorytellerBudget.zone_of_key(key)
			if target == "lot":
				ids = lots_in_zone(zone)
				make = "town_lot"
			else:
				ids = townies_in_zone(zone)
				make = "townie"
	var conds: Array = def.get("conditions", [])
	var good: bool = str(c.get("tone", "bad")) == "good"
	for x in ids:
		var s = IncidentSubject.of_household(int(x)) if make == "household" else (IncidentSubject.of_folk(x) if make == "folk" else (IncidentSubject.of_town_lot(int(x)) if make == "town_lot" else IncidentSubject.of_townie(int(x))))
		if IncidentCond.check(conds, s) and (good or IncidentRisk.risk_factor(def, s) > 0.0):
			out.append(s)
			if first_only:
				break
	return out

# ------------------------------------------------------------------ the context
static func make_ctx(key: String, c: Dictionary, extra: Dictionary) -> Dictionary:
	var kind: String = StorytellerBudget.kind_of(key)
	var ctx: Dictionary = {"key": key, "hid": 0, "folk_id": -1, "other": -1, "lot": 0, "zone": StorytellerBudget.zone_of_key(key), "who": -1, "stat": kind != "home"}
	ctx.merge(extra.get("ctx", {}), true)
	match kind:
		"home":
			ctx["hid"] = StorytellerBudget.id_of(key)
			ctx["folk_id"] = _pick_folk(c, ctx)
		"lot":
			ctx["lot"] = StorytellerBudget.id_of(key)
			var mem: Array = lot_members(int(ctx["lot"]))
			ctx["folk_id"] = int(mem[Storyteller.rng.randi_range(0, mem.size() - 1)]) if not mem.is_empty() else -1
		"district":
			var subs: Array = _incident_subjects(c, key) if c.has("incident") else []
			if not subs.is_empty():
				var s = subs[Storyteller.rng.randi_range(0, subs.size() - 1)]
				ctx["target"] = s
				if s.kind == "townie":
					ctx["who"] = s.id
					ctx["lot"] = int(Story.townies[s.id].get("lot", 0))
				else:
					ctx["lot"] = s.id
					var mem2: Array = lot_members(int(s.id))
					ctx["who"] = int(mem2[0]) if not mem2.is_empty() else -1
			else:
				var pool: Array = townies_in_zone(str(ctx["zone"]))
				if not pool.is_empty():
					ctx["who"] = int(pool[Storyteller.rng.randi_range(0, pool.size() - 1)])
					ctx["lot"] = int(Story.townies[ctx["who"]].get("lot", 0))
	if int(ctx["other"]) < 0:
		ctx["other"] = StorytellerFx.make_other(str(c.get("arrive", "")), ctx)
	return ctx

static func _pick_folk(c: Dictionary, ctx: Dictionary) -> int:
	var res: Array = residents_of(int(ctx["hid"]))
	var def: Dictionary = IncidentDefs.get_def(str(c.get("incident", "")))
	var pool: Array = []
	if not def.is_empty() and str(c.get("target", "lot")) == "folk":
		for f in res:
			if IncidentCond.check(def.get("conditions", []), IncidentSubject.of_folk(f)):
				pool.append(f)
	else:
		pool = _adults(res)
		var when: Dictionary = c.get("when", {})
		if bool(when.get("job", false)):
			pool = pool.filter(func(f): return Careers.has_job(int(f.id)))
	if pool.is_empty():
		pool = res
	return int(pool[Storyteller.rng.randi_range(0, pool.size() - 1)].id) if not pool.is_empty() else -1

# ------------------------------------------------------------------ play
static func card(key: String, cid: String, extra: Dictionary) -> Dictionary:
	var c: Dictionary = StorytellerDeck.card(cid)
	if c.is_empty():
		return {}
	var ctx: Dictionary = make_ctx(key, c, extra)
	Storyteller.played["%s|%s" % [key, cid]] = SysUtil.day()
	if StorytellerLog.foreshadow(key, cid, c, ctx, extra):
		return {"scheduled": true}
	return execute(key, cid, c, ctx, extra)

static func execute(key: String, cid: String, c: Dictionary, ctx: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var was: bool = Storyteller.playing
	Storyteller.playing = true
	var res: Dictionary = {"text": "", "ok": true}
	if c.has("arc"):
		res = StorytellerArcs.start(str(c["arc"]), key, ctx, cid)
	elif c.has("cycle"):
		res = StorytellerCycles.start(str(c["cycle"]), ctx)
	elif c.has("incident"):
		res = _run_incident(c, ctx)
	elif c.has("options") and not bool(ctx["stat"]):
		res = StorytellerChoice.open(key, cid, c, ctx)
	elif c.has("options"):
		res = StorytellerChoice.resolve_option(c, str(c.get("auto", c.get("default", ""))), ctx)
	else:
		res = _run_pure(c, ctx)
	Storyteller.playing = was
	_after(key, cid, c, ctx, res, extra)
	return res

static func _run_incident(c: Dictionary, ctx: Dictionary) -> Dictionary:
	var iid: String = str(c["incident"])
	var key: String = str(ctx["key"])
	var subs: Array = [ctx["target"]] if ctx.has("target") else _incident_subjects(c, key)
	if subs.is_empty():
		return {"text": "", "ok": false}
	var s = subs[0] if ctx.has("target") else _same_target(subs, ctx)
	var fctx: Dictionary = {}
	if s.kind == "folk":
		fctx = {"folk_id": s.id, "warn": str(c.get("size", "small")) != "small" and str(c.get("tone", "")) == "bad"}
		ctx["folk_id"] = s.id
	elif s.kind == "townie":
		fctx = {"townie_id": s.id, "folk_id": s.id}
	else:
		fctx = {"lot": s.lot_key}
	var r: Dictionary = Incidents.force(iid, fctx)
	var text: String = str(r.get("text", ""))
	if text == "":
		text = str(c.get("text", c.get("title", "")))
	if ctx.has("target"):
		ctx.erase("target")
	return {"text": text, "ok": bool(r.get("ok", false)), "incident": iid}

## A foreshadowed card plays on the same lot or person that was chosen when it was drawn (when that is still possible).
static func _same_target(subs: Array, ctx: Dictionary):
	for s in subs:
		if (s.kind == "townie" and int(ctx.get("who", -2)) == s.id) or (s.kind == "lot" and int(ctx.get("lot", -2)) == s.id and str(ctx["key"]).begins_with("d")):
			return s
	return subs[Storyteller.rng.randi_range(0, subs.size() - 1)]

static func _run_pure(c: Dictionary, ctx: Dictionary) -> Dictionary:
	var fx: Array = c.get("fx", [])
	StorytellerFx.apply(fx, ctx)
	var text: String = str(c.get("lot_text", c.get("text", ""))) if bool(ctx["stat"]) and c.has("lot_text") else str(c.get("text", c.get("title", "")))
	if bool(ctx["stat"]) and c.has("lot_fx"):
		StorytellerFx.apply(c["lot_fx"], ctx)
	return {"text": StorytellerFx.fill(text, ctx), "ok": true}

static func _after(key: String, cid: String, c: Dictionary, ctx: Dictionary, res: Dictionary, extra: Dictionary) -> void:
	if not bool(res.get("ok", true)):
		return
	var size: String = str(c.get("size", "small"))
	var tone: String = str(c.get("tone", "mixed"))
	var zone: String = str(ctx["zone"])
	if int(ctx.get("lot", 0)) > 0 and str(ctx["key"]).begins_with("d"):
		zone = CityState.zone_of_town_lot(int(ctx["lot"]))
		ctx["zone"] = zone
	StorytellerBudget.mark(key, size, tone)
	if extra.has("for_key"):
		pass
	for t in c.get("tags", []):
		StorytellerChaos.add_heat(zone, str(t))
	if c.has("ripple"):
		StorytellerRipple.spread(cid, c, ctx, extra)
	StorytellerQueue.chain_from(cid, ctx)
	Storyteller.bump("cards")
	Storyteller.bump("cards_" + size)
	Storyteller.bump("tone_" + tone)
	var scope: String = "home" if StorytellerBudget.kind_of(key) == "home" else ("lot" if StorytellerBudget.kind_of(key) == "lot" else ("town" if key == Storyteller.KEY_TOWN else "city"))
	if not bool(res.get("silent", false)):
		StorytellerLog.event(cid, c, ctx, res, scope, extra)
	if not c.has("incident") and not c.has("cycle") and not c.has("arc") and int(c.get("sev", 1 if size == "small" else 2)) >= 2 and str(res.get("text", "")) != "":
		var subjects: Array = [int(ctx["folk_id"])] if int(ctx["folk_id"]) >= 0 else []
		var lot: String = ("home:%d" % int(ctx["hid"])) if int(ctx["hid"]) > 0 else (("town:%d" % int(ctx["lot"])) if int(ctx["lot"]) > 0 else "town:0")
		ChronicleHook.note(cid, str(res["text"]), subjects, lot, int(c.get("sev", 2)), true)
