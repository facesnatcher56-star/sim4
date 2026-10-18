class_name AccidentRescue
extends RefCounted
## Counterplay for the warned accidents (drowning scare, choking): while the warning is pending the victim carries a "in trouble"
## marker buff (acc_trouble_water / acc_trouble_choke) so a rescue interaction can target them, and nearby awake people may step in
## by themselves (config.accidents.trouble.<incident>: buff, help_per_min, radius). A rescue (this code or the interaction, both leave
## the same state) gives the victim `acc_rescued`, which the incident's `defuse` list reads, and the helper a `hero_moment`.

static func trouble() -> Dictionary:
	return (IncidentDefs.cfg("accidents", {}) as Dictionary).get("trouble", {})

static func all_buffs() -> Array:
	var out: Array = []
	for id in trouble():
		var b: String = str(trouble()[id].get("buff", ""))
		if b != "" and not out.has(b):
			out.append(b)
	return out

static func on_minute() -> void:
	var t: Dictionary = trouble()
	if t.is_empty():
		return
	var live: Dictionary = {}
	for p in Incidents.pending:
		if not t.has(str(p["id"])) or str(p["kind"]) != "folk":
			continue
		var v = SysUtil.folk(int(p["sid"]))
		if v == null:
			continue
		var spec: Dictionary = t[str(p["id"])]
		if bool(p.get("defused", false)) or v.has_buff("acc_rescued"):
			continue
		live[int(v.id)] = true
		AccidentMarks.mark(v, str(spec.get("buff", "")))
		_try_auto_help(v, spec, p)
	# nobody stays "in trouble" once the warning is over or they were rescued
	for f in WorldIface.all_folk():
		for b in all_buffs():
			if f.has_buff(b) and (not live.has(int(f.id)) or f.has_buff("acc_rescued")):
				AccidentMarks.unmark(f, b)

static func helpers_near(victim, radius: float) -> Array:
	var out: Array = []
	for o in AccidentMarks.company(victim, AccidentMarks.helper_stages()):
		var d: float = Vector2(o.tile - victim.tile).length()
		if d <= radius:
			out.append([d, int(o.id), o])
	out.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	return out.map(func(x): return x[2])

static func _try_auto_help(victim, spec: Dictionary, p: Dictionary) -> void:
	var hs: Array = helpers_near(victim, float(spec.get("radius", 14.0)))
	if hs.is_empty():
		return
	if Incidents.rng.randf() < float(spec.get("help_per_min", 0.4)):
		rescue(hs[0], victim, p)

## Whoever acts, the result is the same: the incident is defused, the helper is thanked.
static func rescue(helper, victim, p: Dictionary = {}) -> void:
	victim.add_buff("acc_rescued")
	for b in all_buffs():
		AccidentMarks.unmark(victim, b)
	if not p.is_empty():
		p["defused"] = true
	if helper != null:
		helper.add_buff("hero_moment")
		helper.add_rel(int(victim.id), "friendship", 5.0)
		victim.add_rel(int(helper.id), "friendship", 5.0)
	SysUtil.game_event("accident_rescued", {"folk_id": int(helper.id) if helper != null else -1, "target_id": int(victim.id)})
