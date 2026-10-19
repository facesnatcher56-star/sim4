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
const NEAR_RADIUS := 40           # objects considered around the folk: covers a whole 32x24 lot (diagonal 40); streets use their own 12-tile reach
static var max_scored: int = 120      # hard budget: at most this many candidates are path-scored per choose() (nearest first); tests lower / raise it

static var last_debug: Dictionary = {}   # folk_id -> debug breakdown (see choose())
static var path_queries: int = 0            # path_length queries made by evaluate() (perf tests count them)
static var rng: RandomNumberGenerator = null
static var debug_enabled: bool = true
## true = last_debug lists a row for EVERY candidate (never-examined ones with their bound score, tests use this: TestFixture.reset); false = only
## closed, examined and best rows (the game: building ~150 rows per decision is a large part of its cost).
static var full_debug: bool = false

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
	var memo := _memo_for(folk)
	var key: String = "r|" + def_id + "|" + (str(obj.def_id) if obj != null else "")
	var hit: Variant = memo.get(key, null)
	if hit == null:
		var msg := ""
		var tags := tags_of(def, obj)
		for td in folk.trait_defs():
			for tok in td.get("refuses", []):
				if msg == "" and token_matches(str(tok), def_id, tags, obj, []):
					msg = "%s refuses %s" % [str(td.get("label", "trait")), str(tok)]
		hit = msg
		memo[key] = msg
	if hit != "":
		last_refusal = hit
		return true
	return false

# ---------------------------------------------------------------- candidates
static var _offered_src: Dictionary = {}      # the interactions table _offered_cache was built from
static var _offered_n: int = -1
static var _offered_cache: Dictionary = {}    # object def id -> [the def's "interactions" list it was built from, its size, result]

## Autonomous object interactions that objects of kind `def_id` offer (listed on the object, or naming it in `objects`).
## Static data, so the answer is cached; it is rebuilt when the interactions table, or the object's own list (content
## injection replaces it), changes.
static func _offered_by(def_id: String, defs: Dictionary) -> Array:
	if not is_same(_offered_src, defs) or _offered_n != defs.size():
		_offered_src = defs
		_offered_n = defs.size()
		_offered_cache.clear()
	var listed: Variant = SimEnv.data().object_def(def_id).get("interactions", null)
	var c: Variant = _offered_cache.get(def_id, null)
	if c != null and is_same(c[0], listed) and c[1] == (listed.size() if listed is Array else -1):
		return c[2]
	var out := _offered_uncached(def_id, defs)
	_offered_cache[def_id] = [listed, listed.size() if listed is Array else -1, out]
	return out

static func _offered_uncached(def_id: String, defs: Dictionary) -> Array:
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

static var _actor_tests: Dictionary = {}      # interaction id -> [its "tests" list, the tests that look at the actor only]

## The tests of an interaction that can be decided without a target or object (static per definition, so filtered once).
static func _actor_only_tests(iid: String, d: Dictionary) -> Array:
	var tests: Array = d.get("tests", [])
	var c: Variant = _actor_tests.get(iid, null)
	if c != null and is_same(c[0], tests) and c[2] == tests.size():
		return c[1]
	var keep: Array = []
	for t in tests:
		if not Cond.uses_target(t) and not Cond.uses_object(t):
			keep.append(t)
	_actor_tests[iid] = [tests, keep, tests.size()]
	return keep

## Why `folk` can not do `iid` on ANY target of this kind (cooldown, trait refusal, or one of its own target-independent
## tests failing), "" when it might. `obj_def` is the object kind for object interactions, "" otherwise. Cached in `cache`.
static func _closed_reason(folk, iid: String, d: Dictionary, obj_def: String, cache: Dictionary) -> String:
	var key := iid + "|" + obj_def
	if cache.has(key):
		return cache[key]
	var why := ""
	var cds: Dictionary = folk.cooldowns
	if not cds.is_empty() and SimEnv.now_min() < int(cds.get(iid, -1)):
		why = "cooldown"
	elif not _never_refuses(folk, cache) and refuses(folk, iid, d, null if obj_def == "" else {"def_id": obj_def}):
		why = last_refusal
	else:
		# the target-independent tests belong to the interaction, not to the kind of object: decided once per interaction
		var ok: Dictionary = cache.get("#tests", {})
		cache["#tests"] = ok
		if not ok.has(iid):
			var ctx: Dictionary = cache.get("#ctx", {})
			if ctx.is_empty():
				ctx = {"folk": folk, "object": null, "target": null, "#mood": null}      # one mood computation for all the tests of this decision
				cache["#ctx"] = ctx
			var pass_all := true
			for c in _actor_only_tests(iid, d):
				if not Cond.check_one(c, ctx):
					pass_all = false
					break
			ok[iid] = pass_all
		if not ok[iid]:
			why = "tests failed / reserved / broken"
	cache[key] = why
	return why

## True when none of the folk's traits refuses anything (the usual case): the per-interaction refusal lookups are skipped.
static func _never_refuses(folk, cache: Dictionary) -> bool:
	if cache.has("#nr"):
		return cache["#nr"]
	var memo := _memo_for(folk)
	var v: Variant = memo.get("#never_refuses", null)
	if v == null:
		v = true
		for td in folk.trait_defs():
			if not (td.get("refuses", []) as Array).is_empty():
				v = false
		memo["#never_refuses"] = v
	cache["#nr"] = v
	return v

## All (interaction, target) pairs that exist in the world for this folk, before any test is applied.
## With `closed` (an Array), interactions that are ruled out for every target (see _closed_reason) are not expanded; one
## summary row per such interaction is appended to `closed` instead. This is what choose() uses: it keeps the work per
## decision proportional to what is actually possible rather than to (interactions x folk).
static func gather(folk, closed = null) -> Array:
	var out: Array = []
	var defs: Dictionary = SimEnv.data().interactions()
	var cache: Dictionary = {}
	var offered: Dictionary = {}      # object def id -> interaction ids (computed once per kind of object)
	var near_objs := WorldIface.objects_for(folk, NEAR_RADIUS)          # level aware: own floor (+ other floors in a home), never somebody else's flat
	for o in near_objs:
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
			out.append({"id": iid, "target_id": int(o.id), "kind": "object", "obj": o, "folk": null, "pk": iid + "|" + def_id})
	var others: Array = WorldIface.folk_near(folk)
	for e in _folk_self_defs(defs):
		var iid: String = e[0]
		var d2: Dictionary = e[1]
		var is_self: bool = e[2]
		var romantic: bool = not is_self and RomanceRules.is_romantic_def(d2)
		if closed != null:
			var why2: String = _closed_reason(folk, iid, d2, "", cache)
			if why2 != "":
				closed.append(_closed_row(iid, d2, "", "none" if is_self else "folk", why2))
				continue
		var pk: String = e[3]
		if is_self:
			out.append({"id": iid, "target_id": -1, "kind": "none", "obj": null, "folk": null, "pk": pk})
		else:
			for f2 in others:
				if f2.id != folk.id and not (romantic and not RomanceRules.allowed(int(folk.id), int(f2.id))):
					out.append({"id": iid, "target_id": int(f2.id), "kind": "folk", "obj": null, "folk": f2, "pk": pk})
	return out

static var _fs_src: Dictionary = {}
static var _fs_n: int = -1
static var _fs_list: Array = []        # [iid, def, is_self, "iid|"] of every autonomous interaction aimed at a person / at the actor

## The autonomous folk / self interactions, in table order (static data: rebuilt when the table or one of its entries is replaced).
static func _folk_self_defs(defs: Dictionary) -> Array:
	var ok: bool = is_same(_fs_src, defs) and _fs_n == defs.size()
	if ok:
		for e in _fs_list:
			if not is_same(defs.get(e[0], null), e[1]):
				ok = false
				break
	if ok:
		return _fs_list
	var out: Array = []
	for iid in defs:
		var d2: Dictionary = defs[iid]
		if not bool(d2.get("autonomous", true)):
			continue
		var tk: String = str(d2.get("target", "object"))
		if tk == "folk" or tk == "self":
			out.append([str(iid), d2, tk == "self", str(iid) + "|"])
	_fs_src = defs
	_fs_n = defs.size()
	_fs_list = out
	return out

static var _closed_rows: Dictionary = {}     # iid -> {object kind -> [why, def, row]}: closed rows are the same every decision, shared (read-only)

static func _closed_row(iid: String, d: Dictionary, obj_def: String, kind: String, why: String) -> Dictionary:
	var per: Dictionary = _closed_rows.get(iid, {})
	_closed_rows[iid] = per
	var c: Variant = per.get(obj_def, null)
	if c != null and c[0] == why and is_same(c[1], d):
		return c[2]
	var row := {"interaction": iid, "label": str(d.get("label", iid)), "target_id": -1, "kind": kind, "object": obj_def,
		"skipped": true, "skip_reason": why, "score": 0.0, "sub": {}}
	per[obj_def] = [why, d, row]
	return row

# ---------------------------------------------------------------- scoring
## The part of a score that does not depend on WHICH target an interaction is aimed at: advertised needs, buff / trait
## multipliers, likes and the routine boost. Cached per (interaction, kind of object) for the duration of one choose().
static func _profile(folk, iid: String, d: Dictionary, obj, cache: Dictionary, pk: String = "") -> Dictionary:
	var key: String = pk if pk != "" else iid + "|" + (str(obj.def_id) if obj != null else "")
	if cache.has(key):
		return cache[key]
	if not cache.has("#tmemo"):          # validate the memos and find this folk's trait memo once per decision
		_validate_memo()
		var m := _memo_for(folk)
		if not m.has("#t"):
			m["#t"] = {}
		cache["#tmemo"] = m["#t"]
	var info: Array = _static_info(key, d, obj)
	var tags: Array = info[0]
	var adv: Dictionary = info[1]
	var adv_keys: Array = info[2]
	var base := 0.0
	var top_need := ""
	var top_val := -1.0
	var needs: Dictionary = folk.needs
	for need in adv:
		var u: float = FLAT_URGENCY
		var st: Variant = needs.get(need, null)
		if st != null:
			var span: float = st.max - st.min
			u = 0.0
			if span > 0.0:
				var x: float = (st.max - st.value) / span
				u = x * x * URGENCY_SCALE
		var part: float = u * float(adv[need])
		base += part
		if part > top_val:
			top_val = part
			top_need = str(need)
	var buff_mult := 1.0
	var buff_notes: Array = []
	for b in _buff_mults(folk, cache):
		var am: Dictionary = b[1]
		for k in am:
			if token_matches(str(k), iid, tags, obj, adv_keys):
				buff_mult *= float(am[k])
				buff_notes.append("%s x%.2f" % [b[0], float(am[k])])
	var tp: Array = _trait_part(folk, iid, tags, obj, adv_keys, key, cache["#tmemo"])
	var p := {"base": base, "adv": adv, "top_need": top_need, "buff_mult": buff_mult, "buff_notes": buff_notes,
		"trait_mult": tp[0], "like": tp[1], "trait_notes": tp[2], "rt": Routine.evaluate(folk, iid, tags, _active_routines(folk, cache))}
	# everything of the score except the distance penalty and the memory bias (shared by every target of this kind)
	var rt: Dictionary = p["rt"]
	var c0: float = base * float(p["buff_mult"]) * float(p["trait_mult"]) * float(rt["mult"]) + float(p["like"])
	if base > 0.0 or float(rt["bonus"]) > 0.0:
		c0 += float(rt["bonus"])
	var variety: float = AutonomyVariety.mult(folk, iid, d, obj) * StoryPacing.interaction_mult(folk, d) * SkillInterest.mult(folk, iid, d)      # "bored of it" (data/autonomy_variety.json), skill taste (data/skill_interest.json)
	p["variety"] = variety
	if c0 > 0.0:
		c0 *= variety
	p["c0"] = c0
	p["label"] = str(d.get("label", iid))
	cache[key] = p
	return p

## Debug breakdown of the advertised needs (only built for the few candidates that get a full report).
static func _need_scores(folk, adv: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for need in adv:
		var u := urgency(folk, str(need))
		out[need] = {"urgency": snappedf(u, 0.01), "strength": adv[need], "score": snappedf(u * float(adv[need]), 0.01)}
	return out

## [id, autonomy_mult] of the folk's buffs that carry one (computed once per decision).
static func _buff_mults(folk, cache: Dictionary) -> Array:
	if not cache.has("#buffs"):
		var out: Array = []
		for b in folk.buffs:
			var am: Dictionary = SimEnv.data().buff_def(str(b["id"])).get("autonomy_mult", {})
			if not am.is_empty():
				out.append([b["id"], am])
		cache["#buffs"] = out
	return cache["#buffs"]

## [tags, advertised needs, their keys] of an (interaction, object kind): static data, memoised.
static func _static_info(key: String, d: Dictionary, obj) -> Array:      # callers have validated the memos (_profile)
	var c: Variant = _memo_info.get(key, null)
	if c != null:
		return c
	var adv: Dictionary = d.get("advertises", {})
	if adv.is_empty() and obj != null:
		adv = (SimEnv.data().object_def(str(obj.def_id)).get("advertises", {}) as Dictionary)
	var out := [tags_of(d, obj), adv, adv.keys()]
	_memo_info[key] = out
	return out

## Memo of the parts that depend only on the folk's traits and the (interaction, object kind): [trait_mult, like, notes] and
## the refusal text. Static data, so it survives between decisions; dropped when the data tables change.
static var _memo_data = null
static var _memo_defs: Dictionary = {}
static var _memo: Dictionary = {}

static var _memo_info: Dictionary = {}       # "iid|object kind" -> _static_info

## Drops the memos when the data tables are replaced.
static func _validate_memo() -> void:
	var data = SimEnv.data()
	if not is_same(data, _memo_data) or not is_same(data.interactions(), _memo_defs):
		_memo_data = data
		_memo_defs = data.interactions()
		_memo.clear()
		_memo_info.clear()

static func _memo_for(folk) -> Dictionary:
	_validate_memo()
	var th: int = folk.traits.hash()
	if not _memo.has(th):
		_memo[th] = {}
	return _memo[th]

static func _trait_part(folk, iid: String, tags: Array, obj, adv_keys: Array, key: String, memo: Dictionary) -> Array:
	if memo.has(key):
		return memo[key]
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
	var out := [trait_mult, like, trait_notes]
	memo[key] = out
	return out
## Active routines of the folk, computed once per decision (kept in the profile cache under "#routines").
static func _active_routines(folk, cache: Dictionary) -> Array:
	if not cache.has("#routines"):
		cache["#routines"] = Routine.active_routines(folk)
	return cache["#routines"]

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
	var dest_level: int = folk.level
	if cand["kind"] == "object":
		dest = obj.slot_tile(0) if obj.has_method("slot_tile") else WorldIface.use_tile(obj, 0)
		dest_level = int(obj.level) if "level" in obj else 0
	elif cand["kind"] == "folk":
		dest = (cand["folk"] as Folk).tile
		dest_level = (cand["folk"] as Folk).level
	path_queries += 1
	var dist := WorldIface.path_length(folk.tile, dest, folk.level, dest_level)      # floors count: stairs / lifts are part of the distance
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
	if score > 0.0:
		score *= float(p["variety"])
	var dist_pen: float = DISTANCE_PENALTY * float(dist)
	score -= dist_pen
	var mem_key: String = _memory_key(cand, iid)
	var bias: float = clampf(folk.memory_bias(mem_key), -0.5, 0.5)
	score *= (1.0 + bias)
	rec["score"] = score
	if not detail:
		return rec
	rec["sub"] = {
		"needs": _need_scores(folk, p["adv"]), "base": snappedf(base, 0.01), "buff_mult": snappedf(float(p["buff_mult"]), 0.001),
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
	# 1. distance-free pass: every candidate gets a score with the straight-line lower bound as its distance (an UPPER bound
	#    of the real score); no path query yet.
	var bias_map: Dictionary = folk.memory_bias_map()
	var bias_obj: Dictionary = {}          # target id -> memory bias (clamped), by kind of key
	var bias_folk: Dictionary = {}
	var bias_int: Dictionary = {}
	for k in bias_map:
		var b: float = clampf(clampf(float(bias_map[k]), -Folk.MEMORY_BIAS_LIMIT, Folk.MEMORY_BIAS_LIMIT), -0.5, 0.5)
		var ks: String = str(k)
		if ks.begins_with("obj:"):
			bias_obj[int(ks.substr(4))] = b
		elif ks.begins_with("folk:"):
			bias_folk[int(ks.substr(5))] = b
		elif ks.begins_with("int:"):
			bias_int[ks.substr(4)] = b
	var pending: Array = []
	var gathered := gather(folk, all_rec)
	var fx: int = folk.tile.x
	var fy: int = folk.tile.y
	var native_slot := true
	var first_obj := true
	for cand in _budget(folk, gathered):
		var iid: String = cand["id"]
		var obj = cand["obj"]
		var p: Variant = profiles.get(cand["pk"], null)
		if p == null:
			var d: Dictionary = SimEnv.data().interaction_def(iid)
			if d.is_empty():
				all_rec.append({"interaction": iid, "label": iid, "target_id": cand["target_id"], "kind": cand["kind"],
					"object": str(obj.def_id) if obj != null else "", "skipped": true, "skip_reason": "unknown interaction", "score": 0.0, "sub": {}, "estimated": true})
				continue
			p = _profile(folk, iid, d, obj, profiles, cand["pk"])
		var dx: int
		var dy: int
		var bias := 0.0
		if obj != null:
			if first_obj:
				first_obj = false
				native_slot = obj.has_method("slot_tile")
			var dest: Vector2i = obj.slot_tile(0) if native_slot else WorldIface.use_tile(obj, 0)
			dx = dest.x
			dy = dest.y
			bias = bias_obj.get(int(cand["target_id"]), 0.0)
		elif cand["kind"] == "folk":
			var ft: Vector2i = (cand["folk"] as Folk).tile
			dx = ft.x
			dy = ft.y
			bias = bias_folk.get(int(cand["target_id"]), 0.0)
		else:
			dx = fx
			dy = fy
			bias = bias_int.get(iid, 0.0)
		var score: float = float(p["c0"]) - DISTANCE_PENALTY * float(maxi(absi(fx - dx), absi(fy - dy)))
		if bias != 0.0:
			score *= 1.0 + bias
		if full_debug:
			var row := {"interaction": iid, "label": p["label"], "target_id": cand["target_id"], "kind": cand["kind"],
				"object": str(obj.def_id) if obj != null else "", "skipped": false, "skip_reason": "", "score": score, "sub": {}, "estimated": true}
			all_rec.append(row)
			if score > 0.0:
				pending.append([score, cand, all_rec.size() - 1])
			else:
				row["skipped"] = true
				row["skip_reason"] = "score <= 0"
		elif score > 0.0:
			pending.append([score, cand, -1])
	pending.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	# 2. real path lengths, best bound first, until the bound of the next candidate cannot beat the DETAIL_N-th real score:
	#    the result is exactly what scoring every candidate would give, with a handful of path queries.
	var need: int = DETAIL_N if full_debug else TOP_N       # the pick only depends on the best TOP_N; the debug report wants DETAIL_N
	var kth := -INF
	for e in pending:
		if scored.size() >= need and float(e[0]) <= kth:
			break
		var rec := evaluate(folk, e[1], profiles, false, true)
		var ri: int = e[2]
		if ri >= 0:
			all_rec[ri] = rec
		else:
			ri = all_rec.size()
			all_rec.append(rec)
		if not rec["skipped"]:
			if float(rec["score"]) > 0.0:
				scored.append([rec, e[1], ri])
				if scored.size() >= need:
					scored.sort_custom(func(a, b): return float(a[0]["score"]) > float(b[0]["score"]))
					kth = float(scored[need - 1][0]["score"])
			else:
				rec["skipped"] = true
				rec["skip_reason"] = "score <= 0"
	scored.sort_custom(func(a, b): return float(a[0]["score"]) > float(b[0]["score"]))
	# the debug breakdown is only built for the best DETAIL_N candidates
	var best: Array = []
	var best_idx: Dictionary = {}
	for k in mini(scored.size(), need):
		var full := evaluate(folk, scored[k][1], profiles, true, true)
		all_rec[scored[k][2]] = full
		best_idx[scored[k][2]] = true
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
		# the best candidates first (sorted: nothing else can outscore them, see the bound above), then every other row in gather order
		var rows: Array = best.duplicate()
		for ri in all_rec.size():
			if not best_idx.has(ri):
				rows.append(all_rec[ri])
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
		var lv: int = folk.level
		if c["obj"] != null:
			t = c["obj"].tile
			lv = int(c["obj"].level) if "level" in c["obj"] else 0
		elif c["folk"] != null:
			t = c["folk"].tile
			lv = c["folk"].level
		keyed.append([absi(t.x - folk.tile.x) + absi(t.y - folk.tile.y) + 6 * absi(lv - folk.level), c])
	keyed.sort_custom(func(a, b): return a[0] < b[0])
	var out: Array = []
	for i in max_scored:
		out.append(keyed[i][1])
	return out
