class_name IncidentFlow
extends RefCounted
## What happens after a roll succeeds (or an incident is forced): warning -> pending -> outcome -> record (counters, history,
## chronicle hook, toast per notify_policy, "incident" game event). Used by Incidents / IncidentChecks.

static func _now_text() -> String:
	var m: int = SysUtil.now()
	return "%02d:%02d" % [(m / 60) % 24, m % 60]

## notify_policy: household = only the player's own people / lots | known = people the household has met (default) | town = always | quiet = never.
static func toast_ok(policy: String, subj) -> bool:
	match policy:
		"quiet":
			return false
		"town":
			return true
		"household":
			return subj.household_id > 0 or subj.lot_key.begins_with("home:")
	return subj.known_by_household()

static func toast(def: Dictionary, subj, text: String, kind: String) -> void:
	if text != "" and toast_ok(str(def.get("notify_policy", "known")), subj):
		SysUtil.notify(text, kind)

# ------------------------------------------------------------------ start / warn
## A roll succeeded for `subj`: warn first when the incident has a lead time (full subjects only), else resolve now.
static func start(def_id: String, subj, immediate: bool = false) -> Dictionary:
	var def: Dictionary = IncidentDefs.get_def(def_id)
	var w: Dictionary = def.get("warning", {})
	var lead: int = int(w.get("lead_min", 0))
	var ctx := {"subject": subj, "lot_key": subj.lot_key, "amount": 0}
	if str(w.get("thought", "")) != "" and subj.folk != null:
		SimEnv.emit("thought", int(subj.folk.id), str(w["thought"]))
	if lead > 0 and subj.is_full() and not immediate:
		Incidents.pending.append({"id": def_id, "kind": subj.kind, "sid": subj.id, "lot_key": subj.lot_key, "due_min": SysUtil.now() + lead, "defused": false})
		Incidents._counter(def_id)["warned"] = int(Incidents._counter(def_id)["warned"]) + 1
		toast(def, subj, IncidentEffects.fill(str(w.get("text", "")), ctx), str(w.get("kind", "warn")))
		return {"ok": true, "mode": "warned", "text": str(w.get("text", ""))}
	return resolve(def_id, subj, not subj.is_full(), false)

static func process_pending() -> void:
	var now: int = SysUtil.now()
	var keep: Array = []
	for p in Incidents.pending:
		if int(p["due_min"]) > now:
			keep.append(p)
			continue
		var def: Dictionary = IncidentDefs.get_def(str(p["id"]))
		var subj = _rebuild(p)
		if def.is_empty() or subj == null:
			continue
		var defuse: Array = def.get("defuse", [])
		if bool(p.get("defused", false)) or (not defuse.is_empty() and IncidentCond.check(defuse, subj)) or IncidentRisk.risk_factor(def, subj) <= 0.0:
			var c: Dictionary = Incidents._counter(str(p["id"]))
			c["averted"] = int(c["averted"]) + 1
			var text: String = IncidentEffects.fill(str(def.get("warning", {}).get("averted", "")), {"subject": subj})
			toast(def, subj, text, "good")
			Incidents.record_history({"kind": "averted", "id": str(p["id"]), "label": str(def.get("label", "")), "day": SysUtil.day(), "time": _now_text(),
				"text": text, "subjects": [subj.id], "lot": subj.lot_key, "severity": 1, "public": false, "mode": "full", "forced": false})
			continue
		resolve(str(p["id"]), subj, false, false)
	Incidents.pending = keep

static func _rebuild(p: Dictionary):
	match str(p["kind"]):
		"folk":
			var f = SysUtil.folk(int(p["sid"]))
			return IncidentSubject.of_folk(f) if f != null else null
		"townie":
			return IncidentSubject.of_townie(int(p["sid"]))
		"lot":
			return IncidentSubject.of_household(int(p["sid"])) if str(p["lot_key"]).begins_with("home:") else IncidentSubject.of_town_lot(int(p["sid"]))
	return null

# ------------------------------------------------------------------ resolve (full or statistical)
static func _fallback_outcomes(outs: Array) -> Array:
	var res: Array = []
	for o in outs:
		var c: Dictionary = (o as Dictionary).duplicate(true)
		var effs: Array = []
		for e in c.get("effects", []):
			var ok: bool = true
			for k in e:
				if not IncidentEffects.STAT_SAFE.has(str(k)) or str(k) == "handler":
					ok = false
			if ok:
				effs.append(e)
		c["effects"] = effs
		res.append(c)
	return res

static func resolve(def_id: String, subj, statistical: bool, forced: bool, outcome_index: int = -1) -> Dictionary:
	var def: Dictionary = IncidentDefs.get_def(def_id)
	if def.is_empty() or subj == null:
		return {"ok": false, "mode": "none", "text": "", "summary": ""}
	var outs: Array = def.get("outcomes", [])
	if statistical:
		var st: Array = (def.get("statistical", {}) as Dictionary).get("outcomes", [])
		outs = st if not st.is_empty() else _fallback_outcomes(outs)
	var oc: Dictionary = IncidentEffects.pick(outs, subj, outcome_index)
	if oc.is_empty():
		return {"ok": false, "mode": "statistical" if statistical else "full", "text": "", "summary": ""}
	var f = subj.folk
	var ctx := {"incident": def_id, "def": def, "outcome": oc, "subject": subj, "folk": f, "lot_key": subj.lot_key, "amount": 0, "forced": forced,
		"statistical": statistical, "household_id": int(f.household_id) if f != null else subj.household_id}
	var res: Dictionary = IncidentEffects.run(oc, ctx)
	record(def_id, def, subj, ctx, oc, res, forced, statistical)
	return {"ok": true, "mode": "statistical" if statistical else "full", "text": res["text"], "summary": res["text"], "kind": res["kind"],
		"outcome_index": int(oc.get("index", 0)), "subject": subj.display_name()}

static func record(def_id: String, def: Dictionary, subj, ctx: Dictionary, oc: Dictionary, res: Dictionary, forced: bool, statistical: bool) -> void:
	var c: Dictionary = Incidents._counter(def_id)
	if forced:
		c["forced"] = int(c["forced"]) + 1
	else:
		c["triggered"] = int(c["triggered"]) + 1
	if statistical:
		c["statistical"] = int(c["statistical"]) + 1
	c["last_day"] = SysUtil.day()
	c["last_text"] = str(res["text"])
	var ids: Array = []
	for m in subj.members():
		if ids.size() < 4:
			ids.append(m.id)
	var kind: String = str(res["kind"])
	var sev: int = int(oc.get("severity", def.get("severity", {"bad": 3, "warn": 2}.get(kind, 1))))
	var is_public: bool = bool(def.get("public", true))
	Incidents.record_history({"kind": "incident", "id": def_id, "label": str(def.get("label", def_id)), "day": SysUtil.day(), "time": _now_text(),
		"text": str(res["text"]), "subjects": ids, "lot": subj.lot_key, "severity": sev, "public": is_public, "mode": "statistical" if statistical else "full",
		"forced": forced, "outcome": int(oc.get("index", 0)), "folk_id": subj.id if subj.kind != "lot" else -1, "folk_name": subj.display_name()})
	if str(res["text"]) != "":
		ChronicleHook.note(def_id, str(res["text"]), ids, subj.lot_key, sev, is_public)
		toast(def, subj, str(res["text"]), kind)
	SysUtil.game_event("incident", {"id": def_id, "folk_id": subj.id if subj.kind != "lot" else -1, "lot": subj.lot_key, "outcome": int(oc.get("index", 0)),
		"forced": forced, "statistical": statistical, "text": str(res["text"])})

# ------------------------------------------------------------------ force
static func force(def_id: String, ctx: Dictionary) -> Dictionary:
	var def: Dictionary = IncidentDefs.get_def(def_id)
	if def.is_empty():
		return {"ok": false, "mode": "none", "text": "unknown incident"}
	var idx: int = int(ctx.get("outcome", -1))
	var warn: bool = bool(ctx.get("warn", false))
	match str(def["scope"]):
		"town":
			var total := {"ok": false, "mode": "full", "text": ""}
			var lots: Array = [_lot_subject(ctx.get("lot"))] if ctx.has("lot") else IncidentChecks.lot_subjects()
			for ls in lots:
				if ls == null:
					continue
				var r: Dictionary = resolve(def_id, ls, not ls.is_full(), true, idx)
				if bool(r["ok"]):
					total = r
			return total
		"lot":
			var ls2 = _lot_subject(ctx.get("lot", Economy.primary_household()))
			return resolve(def_id, ls2, not ls2.is_full(), true, idx) if ls2 != null else {"ok": false, "mode": "none", "text": "no such lot"}
		"townie":
			var tid: int = int(ctx.get("townie_id", ctx.get("folk_id", -1)))
			if tid < 0:
				var alive: Array = Story.alive_townies()
				tid = int(alive[0]["id"]) if not alive.is_empty() else -1
			var f2 = SysUtil.folk(tid)
			var s2 = IncidentSubject.of_folk(f2) if f2 != null else IncidentSubject.of_townie(tid)
			return resolve(def_id, s2, not s2.is_full(), true, idx)
	# folk
	var fid: int = int(ctx.get("folk_id", -1))
	var f = SysUtil.folk(fid)
	var subj = null
	if f != null:
		subj = IncidentSubject.of_folk(f)
	elif Story.townies.has(fid):
		subj = IncidentSubject.of_townie(fid)
	else:
		var rs: Array = SysUtil.residents()
		rs.sort_custom(func(a, b): return a.id < b.id)
		if rs.is_empty():
			return {"ok": false, "mode": "none", "text": "nobody to target"}
		subj = IncidentSubject.of_folk(rs[0])
	if warn and subj.is_full():
		return start(def_id, subj, false)
	return resolve(def_id, subj, not subj.is_full(), true, idx)

static func _lot_subject(lot):
	if lot is String and (lot as String).begins_with("town:"):
		return IncidentSubject.of_town_lot(int((lot as String).get_slice(":", 1)))
	if lot is String and (lot as String).begins_with("home:"):
		return IncidentSubject.of_household(int((lot as String).get_slice(":", 1)))
	return IncidentSubject.of_household(int(lot))
