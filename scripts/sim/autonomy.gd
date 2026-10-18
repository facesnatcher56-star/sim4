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
const DETAIL_N := 8               # candidates that get a full debug breakdown in last_debug
static var max_scored: int = 120      # hard budget: at most this many candidates are path-scored per choose() (nearest first); tests lower / raise it

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
## Autonomous object interactions that objects of kind `def_id` offer (listed on the object, or naming it in `objects`).
static func _offered_by(def_id: String, defs: Dictionary) -> Array:
	var od: Dictionary = SimEnv.data().object_def(def_id)
	var ids: Dictionary = {}
	for iid in od.get("interactions", []):
		ids[str(iid)] = true
	for iid in defs:
		if (defs[iid].get("objects", []) as Array).has(def_id):
			ids[str(iid)] = true
	var out: Array = []
	for iid in ids:
		var d: Dictionary = defs.get(iid, {})
		if d.is_empty() or str(d.get("target", "object")) != "object" or not bool(d.get("autonomous", true)):
			continue
		var only: Array = d.get("objects", [])
		if not only.is_empty() and not only.has(def_id):
			continue
		out.append(iid)
	return out

## Why `folk` can not do `iid` on ANY target of this kind (cooldown, trait refusal, or one of its own target-independent
## tests failing), "" when it might. `obj_def` is the object kind for object interactions, "" otherwise. Cached in `cache`.
static func _closed_reason(folk, iid: String, d: Dictionary, obj_def: String, cache: Dictionary) -> String:
	var key := iid + "|" + obj_def
	if cache.has(key):
		return cache[key]
	var why := ""
	if folk.on_cooldown(iid):
		why = "cooldown"
	elif refuses(folk, iid, d, null if obj_def == "" else {"def_id": obj_def}):
		why = last_refusal
	else:
		var ctx := {"folk": folk, "object": null, "target": null}
		for c in d.get("tests", []):
			if not Cond.uses_target(c) and not Cond.uses_object(c) and not Cond.check_one(c, ctx):
				why = "tests failed / reserved / broken"
				break
	cache[key] = why
	return why

## All (interaction, target) pairs that exist in the world for this folk, before any test is applied.
## With `closed` (an Array), interactions that are ruled out for every target (see _closed_reason) are not expanded; one
## summary row per such interaction is appended to `closed` instead. This is what choose() uses: it keeps the work per
## decision proportional to what is actually possible rather than to (interactions x folk).
static func gather(folk, closed = null) -> Array:
	var out: Array = []
	var defs: Dictionary = SimEnv.data().interactions()
	var cache: Dictionary = {}
	var offered: Dictionary = {}      # object def id -> interaction ids (computed once per kind of object)
	for o in WorldIface.objects_near(folk.tile, 200):
		var def_id := str(o.def_id)
		if not offered.has(def_id):
			var open_ids: Array = []
			for iid in _offered_by(def_id, defs):
				var why: String = "" if closed == null else _closed_reason(folk, iid, defs[iid], def_id, cache)
				if why == "":
					open_ids.append(iid)
				else:
					closed.append(_closed_row(iid, defs[iid], def_id, "object", why))
			offered[def_id] = open_ids
		for iid in offered[def_id]:
			out.append({"id": iid, "target_id": int(o.id), "kind": "object", "obj": o, "folk": null})
	var others: Array = WorldIface.folk_near(folk)
	for iid in defs:
		var d2: Dictionary = defs[iid]
		if not bool(d2.get("autonomous", true)):
			continue
		var tk: String = str(d2.get("target", "object"))
		if tk != "folk" and tk != "self":
			continue
		if closed != null:
			var why2: String = _closed_reason(folk, iid, d2, "", cache)
			if why2 != "":
				closed.append(_closed_row(iid, d2, "", "folk" if tk == "folk" else "none", why2))
				continue
		if tk == "self":
			out.append({"id": iid, "target_id": -1, "kind": "none", "obj": null, "folk": null})
		else:
			for f2 in others:
				if f2.id != folk.id:
					out.append({"id": iid, "target_id": int(f2.id), "kind": "folk", "obj": null, "folk": f2})
	return out

static func _closed_row(iid: String, d: Dictionary, obj_def: String, kind: String, why: String) -> Dictionary:
	return {"interaction": iid, "label": str(d.get("label", iid)), "target_id": -1, "kind": kind, "object": obj_def,
		"skipped": true, "skip_reason": why, "score": 0.0, "sub": {}}

# ---------------------------------------------------------------- scoring
## The part of a score that does not depend on WHICH target an interaction is aimed at: advertised needs, buff / trait
## multipliers, likes and the routine boost. Cached per (interaction, kind of object) for the duration of one choose().
static func _profile(folk, iid: String, d: Dictionary, obj, cache: Dictionary) -> Dictionary:
	var key: String = iid + "|" + (str(obj.def_id) if obj != null else "")
	if cache.has(key):
		return cache[key]
	var tags := tags_of(d, obj)
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
	var buff_mult := 1.0
	var buff_notes: Array = []
	for b in folk.buffs:
		var bd: Dictionary = SimEnv.data().buff_def(str(b["id"]))
		var am: Dictionary = bd.get("autonomy_mult", {})
		for k in am:
			if token_matches(str(k), iid, tags, obj, adv_keys):
				buff_mult *= float(am[k])
				buff_notes.append("%s x%.2f" % [b["id"], float(am[k])])
	var trait_mult := 1.0
	var like := 0.0
	var trait_notes: Array = []
	for td in folk.trait_defs():
		var tm: Dictionary = td.get("autonomy_mult", {})
		for k in tm:
			if token_matches(str(k), iid, tags, obj, adv_keys):
				trait_mult *= float(tm[k])
				trait_notes.append("%s x%.2f" % [str(td.get("label", "")), float(tm[k])])
		for tok in td.get("likes", []):
			if token_matches(str(tok), iid, tags, obj, []):
				like += LIKE_BONUS
				trait_notes.append("%s likes %s" % [str(td.get("label", "")), tok])
		for tok in td.get("dislikes", []):
			if token_matches(str(tok), iid, tags, obj, []):
				like += DISLIKE_BONUS
				trait_notes.append("%s dislikes %s" % [str(td.get("label", "")), tok])
	var p := {"base": base, "need_scores": need_scores, "top_need": top_need, "buff_mult": buff_mult, "buff_notes": buff_notes,
		"trait_mult": trait_mult, "like": like, "trait_notes": trait_notes, "rt": Routine.evaluate(folk, iid, tags)}
	cache[key] = p
	return p

static func _memory_key(cand: Dictionary, iid: String) -> String:
	match str(cand["kind"]):
		"object":
			return "obj:%d" % int(cand["target_id"])
		"folk":
			return "folk:%d" % int(cand["target_id"])
	return "int:%s" % iid

## Score one candidate. Returns a debug dictionary with "skipped" (bool), "skip_reason", "score", "sub".
## `profiles` shares _profile() results between candidates; `detail` = false skips the debug breakdown ("sub", "reason");
## `prechecked` = cooldown and trait refusal were already settled by gather()'s closed-interaction pass.
static func evaluate(folk, cand: Dictionary, profiles: Dictionary = {}, detail: bool = true, prechecked: bool = false) -> Dictionary:
	var iid: String = cand["id"]
	var d: Dictionary = SimEnv.data().interaction_def(iid)
	var obj = cand["obj"]
	var rec := {
		"interaction": iid, "label": str(d.get("label", iid)), "target_id": cand["target_id"], "kind": cand["kind"],
		"object": str(obj.def_id) if obj != null else "", "skipped": false, "skip_reason": "", "score": 0.0, "sub": {},
	}
	if d.is_empty():
		rec["skipped"] = true
		rec["skip_reason"] = "unknown interaction"
		return rec
	if not prechecked:
		if folk.on_cooldown(iid):
			rec["skipped"] = true
			rec["skip_reason"] = "cooldown"
			return rec
		if refuses(folk, iid, d, obj):
			rec["skipped"] = true
			rec["skip_reason"] = last_refusal
			return rec
	if not Interaction.def_runnable(d, folk, obj, cand["folk"]):
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
	var p: Dictionary = _profile(folk, iid, d, obj, profiles)
	var base: float = p["base"]
	var rt: Dictionary = p["rt"]
	var score := base
	score *= float(p["buff_mult"]) * float(p["trait_mult"]) * float(rt["mult"])
	score += float(p["like"])
	if base > 0.0 or float(rt["bonus"]) > 0.0:
		score += float(rt["bonus"])
	var dist_pen: float = DISTANCE_PENALTY * float(dist)
	score -= dist_pen
	var mem_key: String = _memory_key(cand, iid)
	var bias: float = clampf(folk.memory_bias(mem_key), -0.5, 0.5)
	score *= (1.0 + bias)
	rec["score"] = score
	if not detail:
		return rec
	rec["sub"] = {
		"needs": p["need_scores"], "base": snappedf(base, 0.01), "buff_mult": snappedf(float(p["buff_mult"]), 0.001),
		"trait_mult": snappedf(float(p["trait_mult"]), 0.001), "like_bonus": p["like"], "routine_mult": snappedf(float(rt["mult"]), 0.001),
		"routine_bonus": rt["bonus"], "distance": dist, "distance_penalty": snappedf(dist_pen, 0.01),
		"memory_key": mem_key, "memory_bias": snappedf(bias, 0.001),
	}
	# reason string
	var parts: Array = []
	var top_need: String = p["top_need"]
	if top_need != "":
		if folk.needs.has(top_need):
			parts.append("%s %s (%.0f)" % [str(SimEnv.data().needs().get(top_need, {}).get("label", top_need)), "is low" if urgency(folk, top_need) > 3.0 else "ok", folk.get_stat_value(top_need)])
		else:
			parts.append("wants %s" % top_need)
	if not (p["buff_notes"] as Array).is_empty():
		parts.append("buffs: " + ", ".join(p["buff_notes"]))
	if not (p["trait_notes"] as Array).is_empty():
		parts.append("traits: " + ", ".join(p["trait_notes"]))
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
	var profiles: Dictionary = {}
	for cand in _budget(folk, gather(folk, all_rec)):
		var rec := evaluate(folk, cand, profiles, false, true)
		all_rec.append(rec)
		if not rec["skipped"]:
			if float(rec["score"]) > 0.0:
				scored.append([rec, cand, all_rec.size() - 1])
			else:
				rec["skipped"] = true
				rec["skip_reason"] = "score <= 0"
	scored.sort_custom(func(a, b): return float(a[0]["score"]) > float(b[0]["score"]))
	# the debug breakdown is only built for the best DETAIL_N candidates
	var best: Array = []
	for k in mini(scored.size(), DETAIL_N):
		var full := evaluate(folk, scored[k][1], profiles, true, true)
		all_rec[scored[k][2]] = full
		best.append(full)
	scored = best
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

## Keep the max_scored candidates nearest to the folk (cheap Manhattan pre-sort) so a decision never costs more than a fixed
## number of path queries, however many objects / folk share the lot.
static func _budget(folk, cands: Array) -> Array:
	if cands.size() <= max_scored:
		return cands
	var keyed: Array = []
	for c in cands:
		var t: Vector2i = folk.tile
		if c["obj"] != null:
			t = c["obj"].tile
		elif c["folk"] != null:
			t = c["folk"].tile
		keyed.append([absi(t.x - folk.tile.x) + absi(t.y - folk.tile.y), c])
	keyed.sort_custom(func(a, b): return a[0] < b[0])
	var out: Array = []
	for i in max_scored:
		out.append(keyed[i][1])
	return out
