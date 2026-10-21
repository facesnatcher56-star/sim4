class_name IncidentEffects
extends RefCounted
## Runs an incident outcome. FULL mode acts on real Folk / households; STATISTICAL mode acts on Story townie records and far lots
## with the same effect vocabulary and only returns a one-line summary. Effects are dictionaries in an outcome's `effects` list:
##   kill "cause" | injure {severity, reason} | sick {severity, reason} | hospital {severity, reason} | coins_range [lo, hi]
##   handler "name" (+ args {...})   |   thought "text"   |   chance 0..1 (this effect only)   |   any Loot key (add_buff, stat_add, coins_add ...)
## Handlers are Callables registered with Incidents.register_handler() or declared in a data file's "handlers" section:
##   func my_handler(ctx: Dictionary, args: Dictionary) -> Dictionary   # may return {"text": "...", "kind": "bad"} to override the outcome text
## ctx = {incident, subject (IncidentSubject), folk (Folk or null), household_id, lot_key, amount, statistical, forced, def, outcome}.

const EFFECT_KEYS := ["kill", "injure", "sick", "hospital", "coins_range", "handler", "args", "thought", "chance"]
const LOOT_KEYS := ["add_buff", "remove_buff", "target_add_buff", "target_remove_buff", "stat_add", "target_stat_add", "skill_xp", "object_state_add",
	"object_state_set", "object_state_toggle", "coins_add", "relationship_add", "fire_event", "notify", "consume_item"]
const STAT_SAFE := ["kill", "injure", "sick", "hospital", "coins_range", "handler", "args", "chance", "add_buff", "remove_buff", "coins_add"]

## Weighted pick among the outcomes whose `when` holds for the subject. forced_index >= 0 picks that entry. Returns {} when none fit.
static func pick(outcomes: Array, subj, forced_index: int = -1) -> Dictionary:
	if forced_index >= 0 and forced_index < outcomes.size():
		var o: Dictionary = (outcomes[forced_index] as Dictionary).duplicate(true)
		o["index"] = forced_index
		return o
	var items: Array = []
	var weights: Array = []
	for i in outcomes.size():
		var o2: Dictionary = outcomes[i]
		if IncidentCond.check(o2.get("when", []), subj):
			items.append(i)
			weights.append(float(o2.get("weight", 1.0)))
	var total: float = 0.0
	for w in weights:
		total += maxf(float(w), 0.0)
	if items.is_empty() or total <= 0.0:
		return {}
	var roll: float = Incidents.rng.randf() * total
	var chosen: int = int(items[items.size() - 1])
	for k in items.size():
		roll -= maxf(float(weights[k]), 0.0)
		if roll <= 0.0:
			chosen = int(items[k])
			break
	var out: Dictionary = (outcomes[chosen] as Dictionary).duplicate(true)
	out["index"] = chosen
	return out

static func fill(text: String, ctx: Dictionary) -> String:
	var subj = ctx.get("subject", null)
	var nm: String = subj.display_name() if subj != null else "Someone"
	var filled: String = text
	if subj != null and str(subj.kind) in ["folk", "townie"]:
		filled = Sexes.fill(text, int(subj.id))          # {they} {them} {themself}: the right words for a known sex
	return filled.replace("{name}", nm).replace("{house}", subj.house_name() if subj != null else "A house").replace("{amount}", str(int(ctx.get("amount", 0)))) \
		.replace("{lot}", str(ctx.get("lot_key", "")))

# ------------------------------------------------------------------ run
## Apply `outcome` and return {text, kind}. Text comes from `text` (full) or `summary` (statistical), filled in with the ctx.
static func run(outcome: Dictionary, ctx: Dictionary) -> Dictionary:
	var stat: bool = bool(ctx.get("statistical", false))
	var override: Dictionary = {}
	for eff in outcome.get("effects", []):
		if eff.has("chance") and Incidents.rng.randf() > float(eff["chance"]):
			continue
		var res: Dictionary = _stat_effect(eff, ctx) if stat else _full_effect(eff, ctx)
		if not res.is_empty():
			override = res
	var text: String = str(override.get("text", outcome.get("summary", "") if stat else outcome.get("text", "")))
	if stat and text == "":
		text = str(outcome.get("text", ""))
	return {"text": fill(text, ctx), "kind": str(override.get("kind", outcome.get("kind", "info")))}

static func _target_folk(ctx: Dictionary):
	var f = ctx.get("folk", null)
	if f == null and ctx.get("subject") != null:
		var h = ctx["subject"].head()
		if h != null:
			f = h.folk
	return f

static func _full_effect(eff: Dictionary, ctx: Dictionary) -> Dictionary:
	var f = _target_folk(ctx)
	var loot: Dictionary = {}
	var res: Dictionary = {}
	for key in eff:
		var v: Variant = eff[key]
		match str(key):
			"kill":
				if f != null:
					Aging.kill(int(f.id), str(v))
			"injure":
				if f != null:
					Hospital.injure(f, int(v.get("severity", 1)), str(v.get("reason", "")))
			"sick":
				if f != null:
					Hospital.fall_ill(f, int(v.get("severity", 1)), str(v.get("reason", "")))
			"hospital":
				if f != null:
					Hospital.emergency(int(f.id), int(v.get("severity", 2)), str(v.get("reason", "")))
			"coins_range":
				ctx["amount"] = Incidents.rng.randi_range(int(v[0]), int(v[1]))
				var hid: int = int(ctx.get("household_id", 0))
				if hid <= 0 and f != null:
					hid = int(f.household_id)
				if hid > 0:
					Economy.deposit(hid, int(ctx["amount"]), "incident")
			"handler":
				var cb: Callable = Incidents.handler(str(v))
				if cb.is_valid():
					var r: Variant = cb.call(ctx, eff.get("args", {}))
					if r is Dictionary:
						res = r
			"thought":
				if f != null:
					ThoughtVoice.urgent(int(f.id), fill(str(v), ctx))
			"args", "chance":
				pass
			_:
				if LOOT_KEYS.has(str(key)):
					loot[key] = v
	if not loot.is_empty() and f != null:
		Loot.apply([loot], {"folk": f, "object": null, "target": null})
	return res

static func _stat_target(ctx: Dictionary):
	var s = ctx["subject"]
	if s.kind != "lot":
		return s
	var m: Array = s.members()
	return m[Incidents.rng.randi_range(0, m.size() - 1)] if not m.is_empty() else null

static func _stat_effect(eff: Dictionary, ctx: Dictionary) -> Dictionary:
	var tgt = _stat_target(ctx)
	var res: Dictionary = {}
	for key in eff:
		var v: Variant = eff[key]
		match str(key):
			"kill":
				if tgt != null:
					Aging.kill(tgt.id, str(v))
			"injure", "sick", "hospital":
				if tgt != null and (str(key) == "hospital" or int(v.get("severity", 1)) >= int(Hospital.cfg().get("min_admit_severity", 2))):
					Hospital.emergency(tgt.id, int(v.get("severity", 2)), str(v.get("reason", "")))
			"coins_range":
				ctx["amount"] = Incidents.rng.randi_range(int(v[0]), int(v[1]))
				if tgt != null and tgt.kind == "townie":
					tgt.t()["coins"] = int(tgt.t().get("coins", 0)) + int(ctx["amount"])
				elif tgt != null and tgt.folk != null and int(tgt.folk.household_id) > 0:
					Economy.deposit(int(tgt.folk.household_id), int(ctx["amount"]), "incident")
			"coins_add":
				if tgt != null and tgt.kind == "townie":
					tgt.t()["coins"] = int(tgt.t().get("coins", 0)) + int(v)
			"add_buff", "remove_buff":
				if tgt != null and tgt.kind == "townie":
					var arr: Array = tgt.t().get("buffs", [])
					if str(key) == "add_buff" and not arr.has(str(v)):
						arr.append(str(v))
					elif str(key) == "remove_buff":
						arr.erase(str(v))
					tgt.t()["buffs"] = arr
			"handler":
				var cb: Callable = Incidents.handler(str(v))
				if cb.is_valid():
					var r: Variant = cb.call(ctx, eff.get("args", {}))
					if r is Dictionary:
						res = r
	return res
