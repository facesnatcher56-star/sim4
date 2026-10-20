class_name DeathCauses
extends RefCounted
## Data for HOW someone died: data/death_causes.json + data/death_causes/*.json (merged by id). Aging.kill(folk_id, cause) looks the
## cause up here for the notification text, grief (strength tier + days), the emotional memory imprint, the legacy sentence and the
## grave style. Causes are ids like "heart_attack"; "old age" is accepted as "old_age". Unknown causes use the `default` entry.
## Also: kill_townie() for Story townies (no Folk on the map), grieve() and the schema validator.

const DIR := "res://data/death_causes"
const KEYS := ["label", "text", "legacy_text", "grief", "child_text", "memory", "grave_style", "unexpected", "severity", "_doc"]
const CHILD_STAGES := ["toddler", "child", "teen"]

static var _loaded: bool = false
static var causes: Dictionary = {}
static var default_def: Dictionary = {}

static func reset() -> void:
	last_notified = -1
	_loaded = false
	causes = {}
	default_def = {}

static func ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var data = SimEnv.data()
	var paths: Array = ["res://data/death_causes.json"]
	var d := DirAccess.open(DIR)
	if d != null:
		var names: Array = []
		for f in d.get_files():
			if f.ends_with(".json") and not f.begins_with("_"):
				names.append(f)
		names.sort()
		for n in names:
			paths.append(DIR.path_join(n))
	for p in paths:
		var parsed: Variant = data.load_file(p)
		if parsed is Dictionary:
			if parsed.has("default"):
				default_def = (parsed["default"] as Dictionary).duplicate(true)
			for id in (parsed.get("causes", {}) as Dictionary):
				causes[id] = parsed["causes"][id]

static func normalize(cause: String) -> String:
	return cause.strip_edges().to_lower().replace(" ", "_")

static func has_cause(id: String) -> bool:
	ensure()
	return causes.has(normalize(id))

static func ids() -> Array:
	ensure()
	var out: Array = causes.keys()
	out.sort()
	return out

## The merged definition for a cause (default entry fills any missing key).
static func def(cause: String) -> Dictionary:
	ensure()
	var cid: String = normalize(cause)
	var d: Dictionary = default_def.duplicate(true)
	if causes.has(cid):
		d.merge(causes[cid], true)
	else:
		d["label"] = cause.capitalize() if cause != "" else str(d.get("label", "Unknown"))
	d["id"] = cid
	return d

static func fill(text: String, name: String, cdef: Dictionary, summary: String = "", dead_id: int = -1) -> String:
	var out: String = text.replace("{name}", name).replace("{cause}", str(cdef.get("label", "")).to_lower()).replace("{summary}", summary).strip_edges()
	return Sexes.fill(out, dead_id) if dead_id >= 0 else out

# ------------------------------------------------------------------ grief
static func grief_buff(strength: float) -> String:
	if strength <= 1.0:
		return str(Aging.cfg().get("grief", {}).get("buff", "grieving"))
	return "grieving_heavy" if strength <= 1.6 else "grieving_shattered"

## Grief, an emotional memory and (for kids) an age-appropriate thought. closeness 1 = family / partner, ~0.6 friend, ~0.5 acquaintance of a townie.
static func grieve(mourner, dead_id: int, dead_name: String, cdef: Dictionary, closeness: float) -> void:
	if mourner == null or str(mourner.age_stage) == "baby":
		return
	var g: Dictionary = cdef.get("grief", {})
	var buff: String = grief_buff(float(g.get("strength", 1.0)))
	var had: bool = mourner.has_buff(buff)
	mourner.add_buff(buff)
	var mins: float = float(g.get("days", 3)) * 1440.0 * closeness
	for b in mourner.buffs:
		if str(b["id"]) == buff:
			b["remaining"] = maxf(float(b["remaining"]), mins) if had else mins
	mourner.add_to_stat("fun", -15.0 * float(g.get("strength", 1.0)) * closeness)
	var mem: Dictionary = cdef.get("memory", {})
	Emotions.imprint(mourner, "folk:%d" % dead_id, float(mem.get("value", -0.5)) * closeness, "death", "sad", fill(str(mem.get("text", "")), dead_name, cdef, "", dead_id))
	RelationshipService.add_history(int(mourner.id), dead_id, "death", float(mem.get("value", -0.5)), dead_id)
	if CHILD_STAGES.has(str(mourner.age_stage)) and str(cdef.get("child_text", "")) != "":
		ThoughtVoice.urgent(int(mourner.id), Sexes.fill(str(cdef["child_text"]), dead_id))

## Closeness of a resident to the dead (0 = does not mourn).
static func closeness(resident_id: int, dead_id: int) -> float:
	var bit: String = RelationshipBits.bit_for(resident_id, dead_id)
	if bit in ["family", "spouse", "partner", "sweetheart", "best_friend"]:
		return 1.0
	var gmin: float = float(Aging.cfg().get("grief", {}).get("min_friendship", 50))
	var fr: float = RelationshipService.value(resident_id, dead_id, "friendship")
	if fr >= gmin:
		return 0.6
	return 0.0

# ------------------------------------------------------------------ townies
static var last_notified: int = -1      # the townie whose death the household was just told about (CaseDiscovery then does not say it again)

## A Story townie dies (no Folk on the map): record, grief for residents who knew them, a park grave, chronicle. Returns a legacy-like dict.
static func kill_townie(tid: int, cause: String) -> Dictionary:
	var t: Dictionary = Story.townies.get(tid, {})
	if t.is_empty() or not bool(t.get("alive", false)):
		return {}
	var cdef: Dictionary = def(cause)
	var nm: String = str(t["name"])
	t["alive"] = false
	t["died_day"] = SysUtil.day()
	t["cause"] = str(cdef["id"])
	var mourners: Array = []
	for r in SysUtil.residents():
		var c: float = closeness(int(r.id), tid)
		if c <= 0.0 and RelationshipService.knows(int(r.id), tid) and RelationshipService.value(int(r.id), tid, "friendship") >= 20.0:
			c = 0.5
		if c > 0.0:
			mourners.append(int(r.id))
			grieve(r, tid, nm, cdef, c)
	var text: String = fill(str(cdef.get("text", "")), nm, cdef, "", tid)
	Story._log("%s passed away (%s)." % [nm, str(cdef.get("label", "")).to_lower()])
	if not mourners.is_empty():
		SysUtil.notify(text, "death")
		last_notified = tid
	var legacy: Dictionary = {"folk_id": tid, "name": nm, "cause": str(cdef.get("label", "")), "cause_id": str(cdef["id"]), "day": SysUtil.day(),
		"mourners": mourners, "townie": true, "legacy_text": Sexes.fill(str(cdef.get("legacy_text", "")), tid), "summary": text}
	Graves.place_for(legacy, null, cdef)
	ChronicleHook.note("death", text if text != "" else "%s died." % nm, [tid], "town:%d" % int(t.get("lot", 0)), int(cdef.get("severity", 3)), true)
	SysUtil.game_event("died", {"folk_id": tid, "cause": str(cdef["id"]), "townie": true})
	DeadPools.purge(tid)
	return legacy

# ------------------------------------------------------------------ validation
static func validate_all() -> Array:
	ensure()
	var errs: Array = []
	if default_def.is_empty():
		errs.append("death_causes: missing default entry")
	var all: Dictionary = causes.duplicate()
	all["default"] = default_def
	for id in all:
		var d: Dictionary = all[id]
		for k in d:
			if not KEYS.has(str(k)):
				errs.append("death cause '%s': unknown key '%s'" % [id, k])
		for need in ["label", "text", "grief", "memory", "grave_style"]:
			if not d.has(need) and id != "default" and not default_def.has(need):
				errs.append("death cause '%s': missing '%s'" % [id, need])
		var g: Dictionary = d.get("grief", {})
		if d.has("grief") and (float(g.get("strength", 0)) <= 0.0 or float(g.get("days", 0)) <= 0.0):
			errs.append("death cause '%s': grief needs strength and days > 0" % id)
		if d.has("grave_style") and not (str(d["grave_style"]) in ["stone", "urn"]):
			errs.append("death cause '%s': grave_style must be stone or urn" % id)
	return errs
