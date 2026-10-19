class_name StorytellerArcs
extends RefCounted
## Arcs: multi-day stories with a setup, an escalation, a climax (a choice for the player, `auto` for townies) and a resolution (data/storyteller_arcs.json),
## advanced once a day on top of the same plumbing StoryThreads uses (visits, relationships, the chronicle). Slots: at most ONE arc per household at a time (key
## "h<id>") and ONE town arc (key "town"). Arcs are only started by the deck, so they are a smaller share of what happens; the category "arcs" and the arc's own
## category can be switched off. Admirer: safety first and non-sexual, it ends with the police or a resolution.

static var active: Dictionary = {}       # slot key -> {arc, stage, due, other, folk_id, hid, zone, lot, who, started}
static var finished: int = 0

static func reset() -> void:
	active.clear()
	finished = 0

static func defs() -> Dictionary:
	return SysUtil.table("storyteller_arcs").get("arcs", {})

static func def(arc_id: String) -> Dictionary:
	return defs().get(arc_id, {})

static func slot_of(key: String) -> String:
	return Storyteller.KEY_TOWN if key == Storyteller.KEY_TOWN else key

static func has_arc(key: String) -> bool:
	return active.has(slot_of(key))

static func can_start(arc_id: String, key: String) -> bool:
	var d: Dictionary = def(arc_id)
	if d.is_empty() or not Storyteller.cat_on("arcs") or has_arc(key):
		return false
	if bool(d.get("mature", false)) and not PregnancyLoss.mature_enabled():
		return false
	var town: bool = key == Storyteller.KEY_TOWN
	if town != (str(d.get("scope", "home")) == "town"):
		return false
	if str(d.get("needs", "none")) in ["neighbour", "townie", "stranger"] and Story.alive_townies().is_empty():
		return false
	return true

static func _town_zone() -> String:
	var ids: Array = CityState.zone_ids()
	return str(ids[Storyteller.rng.randi_range(0, ids.size() - 1)]) if not ids.is_empty() else ""

static func start(arc_id: String, key: String, ctx: Dictionary, _cid: String) -> Dictionary:
	var d: Dictionary = def(arc_id)
	var rec: Dictionary = {"arc": arc_id, "stage": 0, "started": SysUtil.day(), "hid": int(ctx.get("hid", 0)), "folk_id": int(ctx.get("folk_id", -1)),
		"zone": str(ctx.get("zone", "")), "lot": int(ctx.get("lot", 0)), "other": -1, "who": -1}
	var needs: String = str(d.get("needs", "none"))
	if key == Storyteller.KEY_TOWN:
		rec["zone"] = _town_zone()
	match needs:
		"neighbour":
			var near: Array = StorytellerPlay.townies_in_zone(str(rec["zone"])).filter(func(t): return Story.stage_of(Story.townies[t]) in ["adult", "elder"])
			rec["other"] = int(near[Storyteller.rng.randi_range(0, near.size() - 1)]) if not near.is_empty() else StorytellerFx.make_other("rival", ctx)
		"stranger":
			rec["other"] = StorytellerFx.make_other("stranger", ctx)
		"townie":
			var pool: Array = StorytellerPlay.townies_in_zone(str(rec["zone"])).filter(func(t): return Story.stage_of(Story.townies[t]) in ["adult", "elder"])
			if pool.is_empty():
				pool = Story.alive_townies().filter(func(t): return Story.stage_of(t) == "adult").map(func(t): return int(t["id"]))
			pool.sort()
			rec["other"] = int(pool[Storyteller.rng.randi_range(0, pool.size() - 1)]) if not pool.is_empty() else -1
	if int(rec["other"]) >= 0 and Story.townies.has(int(rec["other"])):
		rec["lot"] = int(Story.townies[int(rec["other"])].get("lot", 0))
		if str(rec["zone"]) == "":
			rec["zone"] = CityState.zone_of_town_lot(int(rec["lot"]))
	rec["who"] = rec["other"]
	rec["due"] = SysUtil.day() + _after(d, 0)
	active[slot_of(key)] = rec
	Storyteller.bump("arcs_started")
	return {"text": "", "ok": true, "silent": true}

static func _after(d: Dictionary, stage: int) -> int:
	var st: Array = d.get("stages", [])
	if stage >= st.size():
		return 1
	var a: Array = (st[stage] as Dictionary).get("after", [1, 2])
	return Storyteller.rng.randi_range(int(a[0]), int(a[1]))

static func _ctx_of(slot: String, rec: Dictionary) -> Dictionary:
	return {"key": slot, "hid": int(rec["hid"]), "folk_id": int(rec["folk_id"]), "other": int(rec["other"]), "lot": int(rec["lot"]), "zone": str(rec["zone"]),
		"who": int(rec["who"]), "stat": slot == Storyteller.KEY_TOWN}

## The pseudo-card of a choice stage ("arc:<id>:<stage>"), so the generic choice code can ask and answer it.
static func stage_card(cid: String) -> Dictionary:
	var parts: PackedStringArray = cid.split(":")
	if parts.size() < 3:
		return {}
	var st: Array = def(parts[1]).get("stages", [])
	var i: int = int(parts[2])
	if i >= st.size():
		return {}
	var s: Dictionary = (st[i] as Dictionary).duplicate(true)
	s["title"] = str(def(parts[1]).get("label", ""))
	s["cat"] = "arcs"
	return s

static func on_day(day: int) -> void:
	var slots: Array = active.keys()
	slots.sort()
	for slot in slots:
		var rec: Dictionary = active[slot]
		if int(rec["due"]) > day:
			continue
		_stage(str(slot), rec, day)

static func _stage(slot: String, rec: Dictionary, day: int) -> void:
	var d: Dictionary = def(str(rec["arc"]))
	var stages: Array = d.get("stages", [])
	var i: int = int(rec["stage"])
	var broken: bool = d.is_empty() or i >= stages.size() or (slot != Storyteller.KEY_TOWN and StorytellerPlay.residents_of(int(rec["hid"])).is_empty())
	if not broken and int(rec["other"]) >= 0 and not (Story.townies.has(int(rec["other"])) and bool(Story.townies[int(rec["other"])]["alive"])):
		broken = true
	if broken or not Storyteller.cat_on("arcs") or not Storyteller.cat_on(str(d.get("cat", "arcs"))):
		active.erase(slot)
		return
	var st: Dictionary = stages[i]
	var ctx: Dictionary = _ctx_of(slot, rec)
	var was: bool = Storyteller.playing
	Storyteller.playing = true
	var text: String = StorytellerFx.fill(str(st.get("text", "")), ctx)
	if st.has("options"):
		var cid: String = "arc:%s:%d" % [rec["arc"], i]
		var card: Dictionary = stage_card(cid)
		if slot == Storyteller.KEY_TOWN or Players.player_of(int(rec["hid"])) < 0:
			var res: Dictionary = StorytellerChoice.resolve_option(card, str(card.get("auto", card.get("default", ""))), ctx)
			text += " " + str(res.get("outcome", ""))
		else:
			StorytellerChoice.open(slot, cid, card, ctx)
	else:
		StorytellerFx.apply(st.get("fx", []), ctx)
	Storyteller.playing = was
	_announce(slot, rec, d, text)
	StorytellerBudget.mark(slot if slot != Storyteller.KEY_TOWN else Storyteller.KEY_TOWN, "medium", "mixed")
	if bool(st.get("end", false)):
		active.erase(slot)
		finished += 1
		Storyteller.bump("arcs_finished")
		return
	rec["stage"] = i + 1
	rec["due"] = day + _after(d, i + 1)
	active[slot] = rec

static func _announce(slot: String, rec: Dictionary, d: Dictionary, text: String) -> void:
	if text.strip_edges() == "":
		return
	var hids: Array = []
	if slot == Storyteller.KEY_TOWN:
		for hid in CityState.full_households():
			if StorytellerDistrict.distance(CityState.zone_of_household(int(hid)), str(rec["zone"])) <= int(StorytellerRipple.rcfg().get("near_zones", 0)):
				hids.append(int(hid))
				StorytellerLog.toast(int(hid), text)
				StorytellerBudget.entry("h%d" % int(hid))["last_notable"] = SysUtil.day()
		Story._log(text)
	else:
		hids = [int(rec["hid"])]
		StorytellerLog.toast(int(rec["hid"]), text)
	StorytellerLog.add("arc", text, str(d.get("label", "")), slot, hids, "town" if slot == Storyteller.KEY_TOWN else "home", "arc_" + str(rec["arc"]))

## After a climax choice nothing else is needed: the resolution stage is already scheduled. Kept for symmetry with cards.
static func to_dict() -> Dictionary:
	return {"active": active.duplicate(true), "finished": finished}

static func from_dict(d: Dictionary) -> void:
	active.clear()
	finished = int(d.get("finished", 0))
	for k in d.get("active", {}):
		var r: Dictionary = (d["active"][k] as Dictionary).duplicate(true)
		SysUtil.ints_in(r, ["stage", "due", "other", "folk_id", "hid", "lot", "who", "started"])
		active[str(k)] = r
