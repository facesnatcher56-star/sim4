class_name PersonActs
extends RefCounted
## Task 53: physical acts on people (data/person_acts.json): shove, punch, pick a pocket, grab a bag, threaten, demand money, follow, take a photo.
## Offered on anyone the pawn can reach, whatever the relationship; nothing says how it will go. The target reacts by their own nature (fight back,
## confront, flee, call the police, shrug: Notice.react "person"), witnesses who really see it may step in or call it in, and whatever is reported
## becomes a case through justice (assault, theft, robbery, threats, harassment). A pocket picked clean and unnoticed stays unnoticed.
##   PersonActs.entries(f, target)      PersonActs.on_minute() (following someone)

static var following: Dictionary = {}          # fid -> {tid, next_min, check_min}

static func reset() -> void:
	following = {}

static func busy() -> bool:
	return not following.is_empty()

static func cfg() -> Dictionary:
	return SysUtil.table("person_acts")

static func _act(id: String) -> Dictionary:
	return (cfg().get("acts", {}) as Dictionary).get(id, {})

static func _say(k: String, d: Dictionary, vars: Dictionary) -> String:
	var lines: Array = d.get(k, [])
	if lines.is_empty():
		return ""
	var t: String = str(lines[PlayerPrompt._pick("person|%s|%s" % [str(d.get("label", "")), k], lines.size())])
	for v in vars:
		t = t.replace("{%s}" % v, str(vars[v]))
	return t

static func entries(f, target) -> Array:
	if f == null or target == null or not Pawn.is_pawn(f) or int(target.id) == int(f.id) or not (target is Folk):
		return []
	var fid: int = int(f.id)
	var out: Array = []
	for id in cfg().get("acts", {}):
		var d: Dictionary = _act(str(id))
		if str(d.get("needs", "")) == "phone" and not PhoneOwn.has_phone(fid):
			continue
		var aid: String = str(id)
		var label: String = str(d.get("label", aid))
		if aid == "follow" and int(following.get(fid, {}).get("tid", -1)) == int(target.id):
			out.append({"id": "stop_follow", "label": "Stop following", "category": "Physical", "enabled": true, "reason": "", "action": func(): following.erase(fid)})
			continue
		out.append({"id": "act_" + aid, "label": label, "category": "Physical", "enabled": true, "reason": "",
			"action": func(): _start(f, target, aid)})
	return out

static func _start(f, target, aid: String) -> void:
	var d: Dictionary = _act(aid)
	if bool(d.get("close", false)):
		WalkThen.go(f, WalkThen.near(target.tile), func(): do_act(f, target, aid))
	else:
		do_act(f, target, aid)

static func do_act(f, target, aid: String) -> void:
	var d: Dictionary = _act(aid)
	var fid: int = int(f.id)
	var tid: int = int(target.id)
	var tn: String = str(target.name).get_slice(" (", 0)
	if aid == "follow":
		following[fid] = {"tid": tid, "next_min": SysUtil.now(), "check_min": SysUtil.now() + int(cfg().get("follow_check_min", 6))}
		return
	var ok: bool = true
	var r: Dictionary = {}
	if d.has("check"):
		r = SkillCheck.attempt(fid, str(d["check"]), {"opponent": tid, "wants": "unseen" if bool(d.get("secret", false)) else ""})
		ok = bool(r["ok"])
	var coins: int = 0
	if ok and d.has("coins"):
		var cr: Array = d["coins"]
		coins = mini(CrimePerson.coins(tid), SysUtil.rng.randi_range(int(cr[0]), int(cr[1])))
		if coins > 0:
			CrimePerson.pay(tid, coins, "taken")
			CrimePerson.add_coins(fid, coins, "taken from %s" % tn)
	var key: String = "line_ok" if ok and d.has("line_ok") else ("line_fail" if not ok and d.has("line_fail") else "line")
	if ok and d.has("coins") and coins <= 0 and d.has("line_none"):
		key = "line_none"
	var text: String = _say(key, d, {"t": tn, "c": coins})
	if text != "":
		SysUtil.notify(text, "story" if bool(d.get("secret", false)) else "bad")
	if ok and int(d.get("injure", 0)) > 0:
		Health.injure(target, int(d["injure"]), aid)
	RelationshipService.add_value(tid, fid, "friendship", float(d.get("friendship", -5)))
	# who knows: a secret act that worked is only known if someone saw it; anything else, the target knows
	var victim_knows: bool = not (bool(d.get("secret", false)) and ok)
	if victim_knows and d.has("victim_buff"):
		CrimePerson.add_buff_safe(tid, str(d["victim_buff"]))
	var witnesses: Array = Notice.who(fid, f.tile, {"noise": float(d.get("noise", 0.3)), "visibility": float(d.get("visibility", 0.8)), "unseen": bool(d.get("secret", false)), "ignore": [tid]})
	_react(f, target, aid, d, victim_knows, witnesses, coins)

static func _react(f, target, aid: String, d: Dictionary, victim_knows: bool, witnesses: Array, coins: int) -> void:
	var fid: int = int(f.id)
	var tid: int = int(target.id)
	var reported: bool = false
	var wid: int = int(witnesses[0]["id"]) if not witnesses.is_empty() else -1
	if victim_knows:
		var re: Dictionary = Notice.react(tid, fid, str(d.get("table", "person")), "victim")
		if str(re["line"]) != "":
			SysUtil.notify(str(re["line"]), "bad")
		match str(re["id"]):
			"fight":
				var back: Dictionary = SkillCheck.attempt(tid, "fight", {"opponent": fid})
				if bool(back["ok"]):
					Health.injure(f, 1, "fight")
				reported = wid >= 0 and SysUtil.rng.randf() < 0.6
			"call":
				reported = true
			"confront":
				reported = wid >= 0 and SysUtil.rng.randf() < 0.3
	if wid >= 0 and not reported:
		var rw: Dictionary = Notice.react(wid, fid, "person", "passerby")
		if str(rw["line"]) != "":
			SysUtil.notify(str(rw["line"]), "bad")
		reported = str(rw["id"]) == "call"
	if (victim_knows or wid >= 0) and d.has("charge"):
		_case(fid, tid, str(d["charge"]), int(d.get("sev", 1)), aid, wid, reported, coins)

## The record: a case that the victim or a witness reported, or one that sits hidden until someone talks.
static func _case(fid: int, tid: int, charge: String, sev: int, aid: String, wid: int, reported: bool, coins: int) -> void:
	var ws: Array = [tid]
	if wid >= 0:
		ws.append(wid)
	var c: Dictionary = CaseStore.create(charge, fid, tid, CrimePlace.where_now(tid), {"witnessed": true, "witnesses": ws, "witness_clarity": 0.9, "trace": 0.3, "stolen_coins": coins, "loot_value": coins})
	c["severity"] = sev
	c["act"] = aid
	CrimePlace.place_at_scene(fid, str(c["scene"]))
	if reported:
		CaseDiscovery.report(c, wid if wid >= 0 else tid, "victim")

# ------------------------------------------------------------------ following someone
static func on_minute() -> void:
	if following.is_empty():
		return
	for fid in following.keys():
		var st: Dictionary = following[fid]
		var f = SysUtil.folk(int(fid))
		var t = SysUtil.folk(int(st["tid"]))
		if f == null or t == null or SysUtil.is_away(t) or (f.current != null and str(f.current.def_id) != "go_here"):
			following.erase(fid)          # they left the map, or the pawn started doing something else
			continue
		var now: int = SysUtil.now()
		if now >= int(st["next_min"]) and Vector2(t.tile - f.tile).length() > 2.0:
			var go: Interaction = Interaction.create_goto(f, WalkThen.near(t.tile), true, int(t.level))
			if go != null:
				f.clear_queue()
				f.enqueue(go)
			st["next_min"] = now + int(cfg().get("follow_every_min", 3))
		if now >= int(st["check_min"]):
			st["check_min"] = now + int(cfg().get("follow_check_min", 6))
			var r: Dictionary = SkillCheck.attempt(int(fid), "sneak", {"opponent": int(t.id), "wants": "unseen"})
			if not bool(r["ok"]):
				following.erase(fid)
				var d: Dictionary = _act("follow")
				SysUtil.notify(_say("line_fail", d, {"t": str(t.name).get_slice(" (", 0)}), "story")
				_react(f, t, "follow", d, true, [], 0)
