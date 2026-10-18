class_name Autonomy
extends RefCounted
## Utility-based autonomous choice. Implements the formula in ARCHITECTURE.md:
##   score = sum(urgency(need) * strength) * buff_mult * trait_mult * routine_mult
##           + like/dislike (+1.5 / -3) + routine_bonus - 0.15 * path_distance
##   score *= (1 + memory_bias)         # in [-0.5, 0.5]
## then weighted-random among the top 3. Everything is recorded in `last_debug[folk_id]`.

const URGENCY_SCALE := 10.0
const FLAT_URGENCY := 1.5          # urgency of non-need advertise keys (fitness, tidy, ambition, creative...)
const LIKE_BONUS := 1.5
const DISLIKE_BONUS := -3.0
const DISTANCE_PENALTY := 0.15
const TOP_N := 3

static var last_debug: Dictionary = {}   # folk_id -> debug breakdown (see choose())
static var rng: RandomNumberGenerator = null
static var debug_enabled: bool = true

static func get_rng() -> RandomNumberGenerator:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	return rng

## urgency(v) = ((max - v)/(max - min))^2 * 10 for needs; flat for non-need advertise keys.
static func urgency(folk, need: String) -> float:
	if folk.needs.has(need):
		var s: Stat = folk.needs[need]
		var span: float = s.max - s.min
		if span <= 0.0:
			return 0.0
		var x: float = (s.max - s.value) / span
		return x * x * URGENCY_SCALE
	return FLAT_URGENCY

# ---------------------------------------------------------------- token matching
static func tags_of(def: Dictionary, obj) -> Array:
	var tags: Array = (def.get("tags", []) as Array).duplicate()
	if obj != null:
		var od: Dictionary = SimEnv.data().object_def(str(obj.def_id))
		for t in od.get("tags", []):
			if not tags.has(t):
				tags.append(t)
	return tags

## token forms: "tag:clean", "interaction:sleep_bed", "object:tv", or a bare need/tag name.
static func token_matches(token: String, def_id: String, tags: Array, obj, advertised: Array) -> bool:
	if token.begins_with("tag:"):
		return tags.has(token.substr(4))
	if token.begins_with("interaction:"):
		return def_id == token.substr(12)
	if token.begins_with("object:"):
		return obj != null and str(obj.def_id) == token.substr(7)
	return tags.has(token) or advertised.has(token)

static var last_refusal: String = ""

static func refuses(folk, def_id: String, def: Dictionary, obj) -> bool:
	var tags := tags_of(def, obj)
	for td in folk.trait_defs():
		for tok in td.get("refuses", []):
			if token_matches(str(tok), def_id, tags, obj, []):
				last_refusal = "%s refuses %s" % [str(td.get("label", "trait")), str(tok)]
				return true
	return false

# ---------------------------------------------------------------- candidates
## All (interaction, target) pairs that exist in the world for this folk, before any test is applied.
static func gather(folk) -> Array:
	var out: Array = []
	var defs: Dictionary = SimEnv.data().interactions()
	for o in WorldIface.objects_near(folk.tile, 200):
		var od: Dictionary = SimEnv.data().object_def(str(o.def_id))
		var ids: Dictionary = {}
		for iid in od.get("interactions", []):
			ids[str(iid)] = true
		for iid in defs:
			if (defs[iid].get("objects", []) as Array).has(str(o.def_id)):
				ids[str(iid)] = true
		for iid in ids:
			var d: Dictionary = defs.get(iid, {})
			if d.is_empty() or str(d.get("target", "object")) != "object":
				continue
			if not bool(d.get("autonomous", true)):
				continue
			var only: Array = d.get("objects", [])
			if not only.is_empty() and not only.has(str(o.def_id)):
				continue
			out.append({"id": iid, "target_id": int(o.id), "kind": "object", "obj": o, "folk": null})
	var others: Array = WorldIface.all_folk()
	for iid in defs:
		var d2: Dictionary = defs[iid]
		if not bool(d2.get("autonomous", true)):
			continue
		var tk: String = str(d2.get("target", "object"))
		if tk == "self":
			out.append({"id": iid, "target_id": -1, "kind": "none", "obj": null, "folk": null})
		elif tk == "folk":
			for f2 in others:
				if f2.id != folk.id:
					out.append({"id": iid, "target_id": int(f2.id), "kind": "folk", "obj": null, "folk": f2})
	return out

# ---------------------------------------------------------------- scoring
## Score one candidate. Returns a debug dictionary with "skipped" (bool), "skip_reason", "score", "sub".
static func evaluate(folk, cand: Dictionary) -> Dictionary:
	var iid: String = cand["id"]
	var d: Dictionary = SimEnv.data().interaction_def(iid)
	var obj = cand["obj"]
	var rec := {
		"interaction": iid, "label": str(d.get("label", iid)), "target_id": cand["target_id"], "kind": cand["kind"],
		"object": str(obj.def_id) if obj != null else "", "skipped": false, "skip_reason": "", "score": 0.0, "sub": {},
	}
	var ir := Interaction.create(iid, folk, int(cand["target_id"]))
	if ir == null:
		rec["skipped"] = true
		rec["skip_reason"] = "unknown interaction"
		return rec
	if cand["kind"] == "folk":
		ir.target_folk = cand["folk"]
	if folk.on_cooldown(iid):
		rec["skipped"] = true
		rec["skip_reason"] = "cooldown"
		return rec
	if refuses(folk, iid, d, obj):
		rec["skipped"] = true
		rec["skip_reason"] = last_refusal
		return rec
	if not ir.can_run(folk, obj, false):
		rec["skipped"] = true
		rec["skip_reason"] = "tests failed / reserved / broken"
		return rec
	# distance
	var dest: Vector2i = folk.tile
	if cand["kind"] == "object":
		dest = WorldIface.use_tile(obj, 0)
	elif cand["kind"] == "folk":
		dest = (cand["folk"] as Folk).tile
	var dist := WorldIface.path_length(folk.tile, dest)
	if dist < 0:
		rec["skipped"] = true
		rec["skip_reason"] = "unreachable"
		return rec
	var tags := tags_of(d, obj)
	# advertised needs
	var adv: Dictionary = d.get("advertises", {})
	if adv.is_empty() and obj != null:
		adv = (SimEnv.data().object_def(str(obj.def_id)).get("advertises", {}) as Dictionary)
	var adv_keys: Array = adv.keys()
	var base := 0.0
	var need_scores: Dictionary = {}
	var top_need := ""
	var top_val := -1.0
	for need in adv:
		var u := urgency(folk, str(need))
		var part: float = u * float(adv[need])
		need_scores[need] = {"urgency": snappedf(u, 0.01), "strength": adv[need], "score": snappedf(part, 0.01)}
		base += part
		if part > top_val:
			top_val = part
			top_need = str(need)
	var score := base
	# buff multipliers
	var buff_mult := 1.0
	var buff_notes: Array = []
	for b in folk.buffs:
		var bd: Dictionary = SimEnv.data().buff_def(str(b["id"]))
		var am: Dictionary = bd.get("autonomy_mult", {})
		for key in am:
			if token_matches(str(key), iid, tags, obj, adv_keys):
				buff_mult *= float(am[key])
				buff_notes.append("%s x%.2f" % [b["id"], float(am[key])])
	# trait multipliers and likes
	var trait_mult := 1.0
	var like := 0.0
	var trait_notes: Array = []
	for td in folk.trait_defs():
		var tm: Dictionary = td.get("autonomy_mult", {})
		for key in tm:
			if token_matches(str(key), iid, tags, obj, adv_keys):
				trait_mult *= float(tm[key])
				trait_notes.append("%s x%.2f" % [str(td.get("label", "")), float(tm[key])])
		for tok in td.get("likes", []):
			if token_matches(str(tok), iid, tags, obj, []):
				like += LIKE_BONUS
				trait_notes.append("%s likes %s" % [str(td.get("label", "")), tok])
		for tok in td.get("dislikes", []):
			if token_matches(str(tok), iid, tags, obj, []):
				like += DISLIKE_BONUS
				trait_notes.append("%s dislikes %s" % [str(td.get("label", "")), tok])
	# routine
	var rt := Routine.evaluate(folk, iid, tags)
	score *= buff_mult * trait_mult * float(rt["mult"])
	score += like
	if base > 0.0 or float(rt["bonus"]) > 0.0:
		score += float(rt["bonus"])
	var dist_pen: float = DISTANCE_PENALTY * float(dist)
	score -= dist_pen
	var mem_key: String = ir.memory_key()
	var bias: float = clampf(folk.memory_bias(mem_key), -0.5, 0.5)
	score *= (1.0 + bias)
	rec["score"] = score
	rec["sub"] = {
		"needs": need_scores, "base": snappedf(base, 0.01), "buff_mult": snappedf(buff_mult, 0.001),
		"trait_mult": snappedf(trait_mult, 0.001), "like_bonus": like, "routine_mult": snappedf(float(rt["mult"]), 0.001),
		"routine_bonus": rt["bonus"], "distance": dist, "distance_penalty": snappedf(dist_pen, 0.01),
		"memory_key": mem_key, "memory_bias": snappedf(bias, 0.001),
	}
	# reason string
	var parts: Array = []
	if top_need != "":
		if folk.needs.has(top_need):
			parts.append("%s %s (%.0f)" % [str(SimEnv.data().needs().get(top_need, {}).get("label", top_need)), "is low" if urgency(folk, top_need) > 3.0 else "ok", folk.get_stat_value(top_need)])
		else:
			parts.append("wants %s" % top_need)
	if not buff_notes.is_empty():
		parts.append("buffs: " + ", ".join(buff_notes))
	if not trait_notes.is_empty():
		parts.append("traits: " + ", ".join(trait_notes))
	if not (rt["names"] as Array).is_empty():
		parts.append("routine: " + ", ".join(rt["names"]))
	if bias != 0.0:
		parts.append("memory %+.2f" % bias)
	var tgt := ""
	if obj != null:
		tgt = " @" + str(SimEnv.data().object_def(str(obj.def_id)).get("label", obj.def_id))
	elif cand["kind"] == "folk":
		tgt = " with " + str((cand["folk"] as Folk).name)
	rec["reason"] = "%s%s: %s" % [rec["label"], tgt, "; ".join(parts)]
	return rec

## Choose what `folk` should do next. Returns {} when nothing is possible, else
## {interaction_id, target_id, target_kind, score, reason, label}.
static func choose(folk) -> Dictionary:
	var scored: Array = []
	var all_rec: Array = []
	for cand in gather(folk):
		var rec := evaluate(folk, cand)
		all_rec.append(rec)
		if not rec["skipped"]:
			if float(rec["score"]) > 0.0:
				scored.append(rec)
			else:
				rec["skipped"] = true
				rec["skip_reason"] = "score <= 0"
	scored.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
	var top: Array = scored.slice(0, TOP_N)
	var picked: Dictionary = {}
	if not top.is_empty():
		var total := 0.0
		for r in top:
			total += float(r["score"])
		var roll := get_rng().randf() * total
		for r in top:
			roll -= float(r["score"])
			if roll <= 0.0:
				picked = r
				break
		if picked.is_empty():
			picked = top[top.size() - 1]
	var result: Dictionary = {}
	if not picked.is_empty():
		result = {
			"interaction_id": picked["interaction"], "target_id": picked["target_id"], "target_kind": picked["kind"],
			"score": picked["score"], "reason": picked["reason"], "label": picked["label"],
		}
	if debug_enabled:
		var rows: Array = []
		for r in all_rec:
			rows.append(r)
		rows.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
		last_debug[folk.id] = {
			"folk": folk.name, "time": SimEnv.clock().time_string(), "candidates": rows,
			"top": top, "picked": picked, "reason": picked.get("reason", "nothing to do"),
			"result": result,
		}
	return result
