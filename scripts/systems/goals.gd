class_name Goals
extends RefCounted
## Aspirations (milestone tracks), whims (short context-generated goals), satisfaction points and the perk shop.
## Pipeline: Events bus -> normalized event -> objectives (count / cond) -> Loot rewards. Data: data/goals.json.
##
## Objective schema (aspiration milestones and whims):
##   {"type":"interaction","id":"cook_meal" | "ids":[...] | "tag":"chore","count":N}
##   {"type":"game_event","name":"promoted","payload_eq":{...},"count":N}
##   {"type":"buff","id":"inspired","count":N}
##   {"type":"cond","cond":[...]}   (SysCond: Cond keys + friends_at_least, bit_count, career_is, ...)

static var profiles: Dictionary = {}   # folk_id -> profile dict

static func reset() -> void:
	profiles.clear()

static func cfg() -> Dictionary:
	return SysUtil.table("goals")

static func settings() -> Dictionary:
	return cfg().get("settings", {})

# ------------------------------------------------------------------ profiles
static func aspiration_ids() -> Array:
	var ids: Array = (cfg().get("aspirations", {}) as Dictionary).keys()
	ids.sort()
	return ids

static func ensure_profile(f) -> Dictionary:
	var fid: int = int(f.id)
	if profiles.has(fid):
		return profiles[fid]
	var best: String = ""
	var best_score: float = -1.0
	for aid in aspiration_ids():
		var sc: float = SysUtil.rng.randf() * 0.5
		for t in cfg()["aspirations"][aid].get("fit_traits", []):
			if f.traits.has(t):
				sc += 1.0
		if sc > best_score:
			best_score = sc
			best = str(aid)
	var p: Dictionary = {"aspiration": best, "ms_index": 0, "ms_progress": 0, "ms_done": [], "whims": [], "points": 0, "lifetime": 0,
		"perks": [], "cooldowns": {}, "whims_done": 0, "next_whim_min": SysUtil.now() + 30}
	profiles[fid] = p
	return p

static func set_aspiration(folk_id: int, aid: String) -> bool:
	var f = SysUtil.folk(folk_id)
	if f == null or not cfg().get("aspirations", {}).has(aid):
		return false
	var p: Dictionary = ensure_profile(f)
	p["aspiration"] = aid
	p["ms_index"] = 0
	p["ms_progress"] = 0
	p["ms_done"] = []
	return true

static func aspiration_label(folk_id: int) -> String:
	var p: Dictionary = profiles.get(folk_id, {})
	if p.is_empty():
		return ""
	return str(cfg().get("aspirations", {}).get(str(p["aspiration"]), {}).get("label", ""))

static func points(folk_id: int) -> int:
	return int((profiles.get(folk_id, {}) as Dictionary).get("points", 0))

static func lifetime_points(folk_id: int) -> int:
	return int((profiles.get(folk_id, {}) as Dictionary).get("lifetime", 0))

static func ensure_all() -> void:
	for f in WorldIface.all_folk():
		if SysUtil.is_resident(f):
			ensure_profile(f)

# ------------------------------------------------------------------ objective engine
## Normalized events: {"type":"interaction","id":..,"tags":[..]} | {"type":"game_event","name":..,"payload":{..}} |
## {"type":"buff","id":..} | {"type":"poll"}
static func _matches(obj: Dictionary, ev: Dictionary) -> bool:
	var t: String = str(obj.get("type", ""))
	if t != str(ev.get("type", "")):
		return false
	match t:
		"interaction":
			if obj.has("id") and str(obj["id"]) != str(ev["id"]):
				return false
			if obj.has("ids") and not (obj["ids"] as Array).has(str(ev["id"])):
				return false
			if obj.has("tag") and not (ev.get("tags", []) as Array).has(str(obj["tag"])):
				return false
			return true
		"game_event":
			if obj.has("name") and str(obj["name"]) != str(ev["name"]):
				return false
			for k in obj.get("payload_eq", {}):
				if str((ev.get("payload", {}) as Dictionary).get(k, "")) != str(obj["payload_eq"][k]):
					return false
			return true
		"buff":
			return not obj.has("id") or str(obj["id"]) == str(ev["id"])
	return false

static func _progress_done(obj: Dictionary, progress: int) -> bool:
	return progress >= int(obj.get("count", 1))

static func objective_target(obj: Dictionary) -> int:
	return int(obj.get("count", 1)) if str(obj.get("type", "")) != "cond" else 1

## Feed one event for one folk. Returns true if anything completed.
static func feed(f, ev: Dictionary) -> void:
	var p: Dictionary = ensure_profile(f)
	_feed_aspiration(f, p, ev)
	_feed_whims(f, p, ev)

static func _feed_aspiration(f, p: Dictionary, ev: Dictionary) -> void:
	var ms: Dictionary = current_milestone(p)
	if ms.is_empty():
		return
	var obj: Dictionary = ms["objective"]
	var done: bool = false
	if str(obj.get("type", "")) == "cond":
		done = SysCond.check(obj.get("cond", []), f)
	elif _matches(obj, ev):
		p["ms_progress"] = int(p["ms_progress"]) + 1
		done = _progress_done(obj, int(p["ms_progress"]))
	if done:
		_complete_milestone(f, p, ms)
		# a freshly unlocked milestone might already be satisfied (cond type)
		var nxt: Dictionary = current_milestone(p)
		if not nxt.is_empty() and str((nxt["objective"] as Dictionary).get("type", "")) == "cond" and SysCond.check(nxt["objective"].get("cond", []), f):
			_feed_aspiration(f, p, {"type": "poll"})

static func current_milestone(p: Dictionary) -> Dictionary:
	var asp: Dictionary = cfg().get("aspirations", {}).get(str(p.get("aspiration", "")), {})
	var ml: Array = asp.get("milestones", [])
	var idx: int = int(p.get("ms_index", 0))
	if idx >= ml.size():
		return {}
	return ml[idx]

static func _complete_milestone(f, p: Dictionary, ms: Dictionary) -> void:
	(p["ms_done"] as Array).append(str(ms["id"]))
	p["ms_index"] = int(p["ms_index"]) + 1
	p["ms_progress"] = 0
	var pts: int = int(ms.get("points", 0))
	p["points"] = int(p["points"]) + pts
	p["lifetime"] = int(p["lifetime"]) + pts
	Loot.apply(ms.get("reward", []), {"folk": f, "object": null, "target": null})
	if SocialFit.player_controlled(f):          # one-character game: other people's milestones are theirs, not a toast
		SysUtil.notify("%s reached a milestone: %s (+%d satisfaction)" % [f.name, str(ms["label"]), pts], "goal")
	SysUtil.game_event("milestone_completed", {"folk_id": f.id, "milestone": ms["id"], "points": pts})
	if current_milestone(p).is_empty():
		SysUtil.notify(Sexes.fill("%s fulfilled {their} aspiration: %s!" % [f.name, aspiration_label(int(f.id))], int(f.id)), "goal")
		SysUtil.game_event("aspiration_completed", {"folk_id": f.id, "aspiration": p["aspiration"]})

static func _feed_whims(f, p: Dictionary, ev: Dictionary) -> void:
	for w in (p["whims"] as Array).duplicate():
		var obj: Dictionary = w["objective"]
		var done: bool = false
		if str(obj.get("type", "")) == "cond":
			done = SysCond.check(obj.get("cond", []), f)
		elif _matches(obj, ev):
			w["progress"] = int(w["progress"]) + 1
			done = _progress_done(obj, int(w["progress"]))
		if done:
			_complete_whim(f, p, w)

static func _complete_whim(f, p: Dictionary, w: Dictionary) -> void:
	(p["whims"] as Array).erase(w)
	var pts: int = int(w["points"])
	p["points"] = int(p["points"]) + pts
	p["lifetime"] = int(p["lifetime"]) + pts
	p["whims_done"] = int(p["whims_done"]) + 1
	var wd: Dictionary = cfg().get("whims", {}).get(str(w["id"]), {})
	var cd_h: float = float(wd.get("cooldown_hours", settings().get("whim_default_cooldown_hours", 18)))
	p["cooldowns"][str(w["id"])] = SysUtil.now() + int(cd_h * 60.0)
	f.add_buff("cheered_up")
	SysUtil.notify("%s fulfilled a whim: %s (+%d)" % [f.name, str(w["label"]), pts], "goal")
	SysUtil.game_event("whim_completed", {"folk_id": f.id, "whim": w["id"], "points": pts})

# ------------------------------------------------------------------ whim generation
## Roll for new whims from the current context (needs, traits, relationships ...).
static func tick_whims(f) -> void:
	var p: Dictionary = ensure_profile(f)
	var s: Dictionary = settings()
	var now: int = SysUtil.now()
	# expire old whims
	for w in (p["whims"] as Array).duplicate():
		if now >= int(w["expires_min"]):
			(p["whims"] as Array).erase(w)
			p["cooldowns"][str(w["id"])] = now + int(float(s.get("whim_default_cooldown_hours", 18)) * 60.0)
	if str(f.age_stage) in ["baby", "toddler"] or SysUtil.is_away(f):
		return
	if (p["whims"] as Array).size() >= int(s.get("max_whims", 3)) or now < int(p["next_whim_min"]):
		return
	var active_ids: Array = []
	for w in p["whims"]:
		active_ids.append(str(w["id"]))
	var ids: Array = []
	var weights: Array = []
	var defs: Dictionary = cfg().get("whims", {})
	for wid in defs:
		var d: Dictionary = defs[wid]
		if active_ids.has(str(wid)) or now < int(p["cooldowns"].get(str(wid), 0)):
			continue
		if not SysCond.check(d.get("when", []), f):
			continue
		var wt: float = float(d.get("weight", 1.0))
		var tw: Dictionary = d.get("trait_weight", {})
		for t in f.traits:
			wt *= float(tw.get(t, 1.0))
		ids.append(str(wid))
		weights.append(wt)
	var pick = SysUtil.pick_weighted(ids, weights)
	p["next_whim_min"] = now + int(float(s.get("whim_slot_stagger_hours", 1)) * 60.0)
	if pick == null:
		return
	_add_whim(f, p, str(pick))

static func _add_whim(f, p: Dictionary, wid: String) -> void:
	var s: Dictionary = settings()
	var d: Dictionary = cfg()["whims"][wid]
	var obj: Dictionary = (d["objective"] as Dictionary).duplicate(true)
	var label: String = str(d["label"])
	match str(d.get("dynamic", "")):
		"skill_next":
			var sk: String = str(d["params"]["skill"])
			var target: int = f.skill_level(sk) + 1
			obj = {"type": "cond", "cond": [{"skill_at_least": [sk, target]}]}
			label = label % target
		"coins_gain":
			var goal: int = WorldIface.get_coins(int(f.household_id)) + int(d["params"]["amount"])
			obj = {"type": "cond", "cond": [{"coins_at_least": goal}]}
	var hours: float = float(d.get("expire_hours", s.get("whim_default_expire_hours", 10)))
	(p["whims"] as Array).append({"id": wid, "label": label, "objective": obj, "progress": 0, "points": int(d.get("points", s.get("whim_default_points", 20))),
		"started_min": SysUtil.now(), "expires_min": SysUtil.now() + int(hours * 60.0)})
	SysUtil.game_event("whim_added", {"folk_id": f.id, "whim": wid})

## Hourly: poll cond-type objectives and roll whims.
static func on_hour() -> void:
	for f in SysUtil.residents():
		var p: Dictionary = ensure_profile(f)
		tick_whims(f)
		feed(f, {"type": "poll"})
		if p.is_empty():
			continue

# ------------------------------------------------------------------ perk shop
static func perk_defs() -> Dictionary:
	return cfg().get("perks", {})

static func owned_perks(folk_id: int) -> Array:
	return (profiles.get(folk_id, {}) as Dictionary).get("perks", [])

static func can_buy(folk_id: int, perk_id: String) -> bool:
	var d: Dictionary = perk_defs().get(perk_id, {})
	var p: Dictionary = profiles.get(folk_id, {})
	if d.is_empty() or p.is_empty() or (p["perks"] as Array).has(perk_id):
		return false
	if int(p["points"]) < int(d.get("cost", 0)):
		return false
	var f = SysUtil.folk(folk_id)
	if f == null:
		return false
	for e in d.get("effects", []):
		if (e as Dictionary).has("add_trait"):
			if f.traits.has(str(e["add_trait"])) or not Aging.can_add_trait(f):
				return false
	return true

static func buy_perk(folk_id: int, perk_id: String) -> bool:
	if not can_buy(folk_id, perk_id):
		return false
	var d: Dictionary = perk_defs()[perk_id]
	var f = SysUtil.folk(folk_id)
	var p: Dictionary = profiles[folk_id]
	p["points"] = int(p["points"]) - int(d.get("cost", 0))
	(p["perks"] as Array).append(perk_id)
	for e in d.get("effects", []):
		var eff: Dictionary = e
		if eff.has("grant_buff"):
			f.add_buff(str(eff["grant_buff"]))
		if eff.has("add_trait"):
			f.traits.append(str(eff["add_trait"]))
		if eff.has("coins_add"):
			Economy.deposit(int(f.household_id), int(eff["coins_add"]), "perk: " + perk_id)
	SysUtil.notify("%s unlocked: %s" % [f.name, str(d.get("label", perk_id))], "goal")
	SysUtil.game_event("perk_bought", {"folk_id": folk_id, "perk": perk_id})
	return true

# ------------------------------------------------------------------ UI
## Everything the HUD needs for the goals panel of one folk.
static func active_for(folk_id: int) -> Dictionary:
	var p: Dictionary = profiles.get(folk_id, {})
	if p.is_empty():
		return {}
	var asp: Dictionary = cfg().get("aspirations", {}).get(str(p["aspiration"]), {})
	var ml: Array = asp.get("milestones", [])
	var cur: Dictionary = current_milestone(p)
	var ms_info: Dictionary = {}
	if not cur.is_empty():
		var obj: Dictionary = cur["objective"]
		var f = SysUtil.folk(folk_id)
		var prog: int = int(p["ms_progress"])
		var tgt: int = objective_target(obj)
		if str(obj.get("type", "")) == "cond":
			prog = 1 if (f != null and SysCond.check(obj.get("cond", []), f)) else 0
		ms_info = {"id": cur["id"], "label": cur["label"], "progress": prog, "target": tgt, "points": cur.get("points", 0)}
	var whims: Array = []
	for w in p["whims"]:
		var wobj: Dictionary = w["objective"]
		whims.append({"id": w["id"], "label": w["label"], "points": w["points"], "progress": w["progress"], "target": objective_target(wobj),
			"expires_min": w["expires_min"], "minutes_left": int(w["expires_min"]) - SysUtil.now()})
	return {"aspiration": str(p["aspiration"]), "aspiration_label": str(asp.get("label", "")), "description": str(asp.get("description", "")),
		"milestone": ms_info, "milestones_done": (p["ms_done"] as Array).size(), "milestones_total": ml.size(),
		"completed": cur.is_empty(), "whims": whims, "points": p["points"], "lifetime_points": p["lifetime"], "perks": (p["perks"] as Array).duplicate(),
		"whims_done": p["whims_done"]}

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {"profiles": SysUtil.str_keys(profiles).duplicate(true)}

static func from_dict(d: Dictionary) -> void:
	reset()
	profiles = SysUtil.int_keys((d.get("profiles", {}) as Dictionary).duplicate(true))
	for k in profiles:
		var p: Dictionary = profiles[k]
		for key in ["ms_index", "ms_progress", "points", "lifetime", "whims_done", "next_whim_min"]:
			p[key] = int(p.get(key, 0))
		var cds: Dictionary = p.get("cooldowns", {})
		for ck in cds:
			cds[ck] = int(cds[ck])
		for w in p["whims"]:
			w["progress"] = int(w["progress"])
			w["points"] = int(w["points"])
			w["started_min"] = int(w["started_min"])
			w["expires_min"] = int(w["expires_min"])
