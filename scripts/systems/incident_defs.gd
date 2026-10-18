class_name IncidentDefs
extends RefCounted
## Loads and validates the incident data: data/incidents.json (config, handlers, content, incidents) merged with every
## data/incidents/*.json in file-name order (incidents by id, later wins per key; handlers by name; content sections by key).
## Schema (per incident): label, scope folk|lot|town|townie, check hour|day, base_rate_per_year, notify_policy, conditions[],
## risk_mults[{when,mult,label}], prevent[{when,mult|block,label}], warning{lead_min,thought,text,kind,averted,doctor_can_defuse},
## defuse[], outcomes[{weight,when,effects[],text,kind}], statistical{outcomes[{weight,when,effects[],summary}]}, surprise (bool).

const DIR := "res://data/incidents"
const SCOPES := ["folk", "lot", "town", "townie"]
const CHECKS := ["hour", "day"]
const POLICIES := ["household", "known", "town", "quiet"]
const TOP_KEYS := ["label", "scope", "check", "base_rate_per_year", "notify_policy", "conditions", "risk_mults", "prevent", "warning", "defuse",
	"outcomes", "statistical", "surprise", "severity", "public", "kind", "tags", "lot_hit", "_doc"]
const OUTCOME_KEYS := ["weight", "when", "effects", "text", "kind", "summary", "id", "severity"]
const WARNING_KEYS := ["lead_min", "thought", "text", "kind", "averted", "doctor_can_defuse"]

static var _loaded: bool = false
static var config: Dictionary = {}
static var defs: Dictionary = {}
static var handler_specs: Dictionary = {}
static var content: Dictionary = {}
static var files: Array = []

static func reset() -> void:
	_loaded = false
	config = {}
	defs = {}
	handler_specs = {}
	content = {}
	files = []

static func ensure() -> void:
	if not _loaded:
		reload()

static func reload() -> void:
	reset()
	_loaded = true
	var data = SimEnv.data()
	var paths: Array = ["res://data/incidents.json"]
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
			files.append(p)
			_merge(parsed)

static func _merge(d: Dictionary) -> void:
	for k in (d.get("config", {}) as Dictionary):
		var v: Variant = d["config"][k]
		if v is Dictionary and config.get(k) is Dictionary:
			(config[k] as Dictionary).merge(v, true)
		else:
			config[k] = v
	for hn in (d.get("handlers", {}) as Dictionary):
		handler_specs[hn] = d["handlers"][hn]
	var inc: Dictionary = d.get("incidents", {})
	for id in inc:
		if defs.has(id):
			(defs[id] as Dictionary).merge(inc[id], true)
		else:
			defs[id] = (inc[id] as Dictionary).duplicate(true)
	var c: Dictionary = d.get("content", {})
	for sec in c:
		if not content.has(sec):
			content[sec] = {}
		for k2 in c[sec]:
			if c[sec][k2] is Array and content[sec].get(k2) is Array:
				for x in c[sec][k2]:
					if not (content[sec][k2] as Array).has(x):
						(content[sec][k2] as Array).append(x)
			else:
				content[sec][k2] = c[sec][k2]

static func ids() -> Array:
	ensure()
	var out: Array = defs.keys()
	out.sort()
	return out

static func get_def(id: String) -> Dictionary:
	ensure()
	return defs.get(id, {})

static func cfg(key: String, default: Variant = null) -> Variant:
	ensure()
	return config.get(key, default)

# ------------------------------------------------------------------ validation
## Every problem found in the loaded data, as readable strings (empty = valid). Used by the schema test.
static func validate_all() -> Array:
	ensure()
	var errs: Array = []
	for hn in handler_specs:
		var sp: Dictionary = handler_specs[hn]
		var scr: Variant = load(str(sp.get("script", ""))) if ResourceLoader.exists(str(sp.get("script", ""))) else null
		if scr == null:
			errs.append("handler '%s': script '%s' not found" % [hn, sp.get("script", "")])
		elif not (scr as Script).has_method(str(sp.get("method", ""))):
			errs.append("handler '%s': no method '%s'" % [hn, sp.get("method", "")])
	for id in ids():
		errs.append_array(validate_def(id, defs[id]))
	return errs

static func validate_def(id: String, d: Dictionary) -> Array:
	var errs: Array = []
	var p: String = "incident '%s': " % id
	for k in d:
		if not TOP_KEYS.has(k):
			errs.append(p + "unknown key '%s'" % k)
	if not SCOPES.has(str(d.get("scope", ""))):
		errs.append(p + "bad scope '%s'" % d.get("scope", ""))
	if not CHECKS.has(str(d.get("check", ""))):
		errs.append(p + "bad check '%s'" % d.get("check", ""))
	if not (d.get("base_rate_per_year", null) is float or d.get("base_rate_per_year", null) is int) or float(d.get("base_rate_per_year", -1)) < 0.0:
		errs.append(p + "base_rate_per_year must be a number >= 0")
	if d.has("notify_policy") and not POLICIES.has(str(d["notify_policy"])):
		errs.append(p + "bad notify_policy '%s'" % d["notify_policy"])
	if str(d.get("label", "")) == "":
		errs.append(p + "missing label")
	errs.append_array(_check_conds(d.get("conditions", []), p + "conditions"))
	errs.append_array(_check_conds(d.get("defuse", []), p + "defuse"))
	for list_key in ["risk_mults", "prevent"]:
		for e in d.get(list_key, []):
			if not (e is Dictionary) or not (e.has("mult") or e.has("block")):
				errs.append(p + "%s entry needs mult or block" % list_key)
				continue
			errs.append_array(_check_conds(e.get("when", []), p + list_key))
	var w: Dictionary = d.get("warning", {})
	for k3 in w:
		if not WARNING_KEYS.has(k3):
			errs.append(p + "unknown warning key '%s'" % k3)
	var outs: Array = d.get("outcomes", [])
	if outs.is_empty():
		errs.append(p + "needs at least one outcome")
	errs.append_array(_check_outcomes(outs, p + "outcomes"))
	if d.has("statistical"):
		errs.append_array(_check_outcomes((d["statistical"] as Dictionary).get("outcomes", []), p + "statistical"))
	return errs

static func _check_conds(conds: Variant, where: String) -> Array:
	var errs: Array = []
	if not (conds is Array):
		return [where + ": must be a list"]
	for c in conds:
		if not (c is Dictionary):
			errs.append(where + ": condition must be an object")
			continue
		for k in c:
			if not IncidentCond.VALID_KEYS.has(str(k)):
				errs.append(where + ": unknown condition key '%s'" % k)
			elif str(k) in ["not"] and c[k] is Dictionary:
				errs.append_array(_check_conds([c[k]], where))
			elif str(k) in ["any", "any_member", "all_members"] and c[k] is Array:
				errs.append_array(_check_conds(c[k], where))
	return errs

static func _check_outcomes(outs: Array, where: String) -> Array:
	var errs: Array = []
	for o in outs:
		if not (o is Dictionary):
			errs.append(where + ": outcome must be an object")
			continue
		for k in o:
			if not OUTCOME_KEYS.has(str(k)):
				errs.append(where + ": unknown outcome key '%s'" % k)
		errs.append_array(_check_conds(o.get("when", []), where))
		for eff in o.get("effects", []):
			for k2 in eff:
				if not IncidentEffects.EFFECT_KEYS.has(str(k2)) and not IncidentEffects.LOOT_KEYS.has(str(k2)):
					errs.append(where + ": unknown effect key '%s'" % k2)
			if eff.has("handler") and not handler_specs.has(str(eff["handler"])) and not Incidents.handlers.has(str(eff["handler"])):
				errs.append(where + ": unknown handler '%s'" % eff["handler"])
			if eff.has("kill") and not DeathCauses.has_cause(str(eff["kill"])):
				errs.append(where + ": unknown death cause '%s'" % eff["kill"])
	return errs
