class_name Emotions
extends RefCounted
## Richer emotions on top of Mood (data/emotions.json):
##  * mood effects  - each mood (by intensity) applies a hidden `mfx_<mood>_<i>` buff carrying need-decay and autonomy multipliers;
##                    skill-gain multipliers are applied as bonus XP when an interaction finishes (skill_mult / on_finished);
##                    interaction availability is plain data: interactions whose tests contain {mood_is: X} are unlocked by X.
##  * contagion     - nearby / conversing folk drift toward each other's strong moods through small `caught_<mood>` buffs.
##  * memory        - strong moments are tied to objects / people / areas (Folk.remember, so Autonomy's memory_bias reacts) and
##                    later produce nostalgia (good) or unease (bad) when the folk meets the same thing again.
##  * journal       - per-day mood minutes -> a short "mood journal" notification at the end of the day.
## All state is static (like the other systems) and saved by RelationshipService.to_dict() under "social".

const FX_PREFIX := "mfx_"

static var moments: Dictionary = {}       # folk_id -> [{key, v, kind, day, mood, label, t, last}]
static var mood_minutes: Dictionary = {}  # folk_id -> {mood: minutes}
static var peaks: Dictionary = {}         # folk_id -> {"best": [mood, intensity], "worst": [mood, intensity]}
static var last_journal: Array = []
static var _ctx_keys: Dictionary = {}     # folk_id -> keys of the interaction in progress (not saved)

static func reset() -> void:
	moments.clear()
	mood_minutes.clear()
	peaks.clear()
	last_journal = []
	_ctx_keys.clear()

# ------------------------------------------------------------------ data helpers
static func cfg() -> Dictionary:
	return SimEnv.data().get_table("emotions")

static func mood_defs() -> Dictionary:
	return cfg().get("moods", {})

static func all_moods() -> Array:
	return Mood.MOODS.duplicate()

static func def_of(mood: String) -> Dictionary:
	return mood_defs().get(mood, {})

static func label(mood: String) -> String:
	return str(def_of(mood).get("label", mood.capitalize()))

static func color(mood: String) -> Color:
	var hex: String = str(def_of(mood).get("color", "#9aa7b4"))
	return Color(hex)

static func valence(mood: String) -> int:
	return int(def_of(mood).get("valence", 0))

static func blurb(mood: String) -> String:
	return str(def_of(mood).get("blurb", ""))

static func scale_for(intensity: int) -> float:
	var arr: Array = cfg().get("intensity_scale", [0.0, 0.6, 1.0, 1.4])
	return float(arr[clampi(intensity, 0, arr.size() - 1)])

static func fx_id(mood: String, intensity: int) -> String:
	return "%s%s_%d" % [FX_PREFIX, mood, intensity]

static func _scaled(v: float, intensity: int) -> float:
	return 1.0 + (v - 1.0) * scale_for(intensity)

## Create the hidden mood-effect buffs in the shared buff table (idempotent).
static func install_buffs(buffs: Dictionary) -> void:
	var defs := mood_defs()
	for m in defs:
		var fx: Dictionary = (defs[m] as Dictionary).get("effects", {})
		for i in range(1, 4):
			var id := fx_id(str(m), i)
			if buffs.has(id):
				continue
			var nd: Dictionary = {}
			for need in fx.get("need_decay_mult", {}):
				var v := _scaled(float(fx["need_decay_mult"][need]), i)
				if absf(v - 1.0) > 0.001:
					nd[need] = snappedf(v, 0.001)
			var am: Dictionary = {}
			for key in fx.get("autonomy_mult", {}):
				var v2 := _scaled(float(fx["autonomy_mult"][key]), i)
				if absf(v2 - 1.0) > 0.001:
					am[key] = snappedf(v2, 0.001)
			buffs[id] = {"label": "Mood: %s %d" % [label(str(m)), i], "mood": {}, "duration_min": 0, "hidden": true, "mood_fx": true,
				"need_decay_mult": nd, "autonomy_mult": am}

## Hidden / marker buffs go to the FRONT of the buff list so that systems which re-add buffs on load (e.g. `away`, always last)
## keep the same order after a save round trip.
static func add_hidden(f, buff_id: String) -> bool:
	if f == null or f.has_buff(buff_id):
		return false
	if not f.add_buff(buff_id):
		return false
	for i in f.buffs.size():
		if str(f.buffs[i]["id"]) == buff_id:
			var e: Dictionary = f.buffs[i]
			f.buffs.remove_at(i)
			f.buffs.push_front(e)
			break
	return true

# ------------------------------------------------------------------ mood -> hidden effect buff
static func sync(f) -> void:
	if f == null:
		return
	f.refresh_mood()
	var want := ""
	var m: String = str(f.mood_name)
	if m != "neutral" and int(f.mood_intensity) > 0 and mood_defs().has(m):
		want = fx_id(m, int(f.mood_intensity))
	for b in f.buffs.duplicate():
		var bid: String = str(b["id"])
		if bid.begins_with(FX_PREFIX) and bid != want:
			f.remove_buff(bid)
	if want != "" and not f.has_buff(want):
		if SimEnv.data().buff_def(want).is_empty():
			install_buffs(SimEnv.data().buffs())
		add_hidden(f, want)

## Active mood-effect numbers for UI text.
static func describe_effects(mood: String, intensity: int) -> Array:
	var out: Array = []
	if mood == "neutral" or not mood_defs().has(mood):
		return out
	var fx: Dictionary = def_of(mood).get("effects", {})
	var sc := scale_for(intensity)
	var sg: Dictionary = fx.get("skill_gain", {})
	var parts: Array = []
	for k in sg:
		var v := _scaled(float(sg[k]), intensity)
		if absf(v - 1.0) >= 0.02:
			parts.append("%s x%.2f" % [("all skills" if k == "*" else str(k)), v])
	if not parts.is_empty():
		out.append("Learning: " + ", ".join(parts))
	var nd: Dictionary = fx.get("need_decay_mult", {})
	parts = []
	for k2 in nd:
		var v2 := _scaled(float(nd[k2]), intensity)
		if absf(v2 - 1.0) >= 0.02:
			parts.append("%s %s" % [k2, "decays faster" if v2 > 1.0 else "decays slower"])
	if not parts.is_empty():
		out.append("Needs: " + ", ".join(parts))
	var am: Dictionary = fx.get("autonomy_mult", {})
	var likes: Array = []
	var avoids: Array = []
	for k3 in am:
		var v3 := _scaled(float(am[k3]), intensity)
		if v3 >= 1.05:
			likes.append(str(k3))
		elif v3 <= 0.95:
			avoids.append(str(k3))
	if not likes.is_empty():
		out.append("Leans toward: " + ", ".join(likes))
	if not avoids.is_empty():
		out.append("Shies away from: " + ", ".join(avoids))
	var un := unlocked_interactions(mood)
	if not un.is_empty():
		out.append("Unlocks: " + ", ".join(un))
	var bl := blocked_interactions(mood)
	if not bl.is_empty():
		out.append("Blocks: " + ", ".join(bl))
	if sc <= 0.0:
		return []
	return out

## Labels of interactions whose tests need {mood_is: mood} (directly or inside an `any`).
static func unlocked_interactions(mood: String) -> Array:
	var out: Array = []
	var defs: Dictionary = SimEnv.data().interactions()
	for iid in defs:
		var tests: Array = (defs[iid] as Dictionary).get("tests", [])
		if _tests_need_mood(tests, mood):
			out.append(str((defs[iid] as Dictionary).get("label", iid)))
	out.sort()
	return out

static func blocked_interactions(mood: String) -> Array:
	var out: Array = []
	var defs: Dictionary = SimEnv.data().interactions()
	for iid in defs:
		var tests: Array = (defs[iid] as Dictionary).get("tests", [])
		for t in tests:
			if t is Dictionary and (t as Dictionary).has("not") and t["not"] is Dictionary and str((t["not"] as Dictionary).get("mood_is", "")) == mood:
				out.append(str((defs[iid] as Dictionary).get("label", iid)))
	out.sort()
	return out

static func _tests_need_mood(tests: Array, mood: String) -> bool:
	for t in tests:
		if not (t is Dictionary):
			continue
		var d: Dictionary = t
		if str(d.get("mood_is", "")) == mood:
			return true
		if d.has("any"):
			for sub in d["any"]:
				if sub is Dictionary and str((sub as Dictionary).get("mood_is", "")) == mood:
					return true
	return false

# ------------------------------------------------------------------ skill gain
static func skill_mult(f, skill: String) -> float:
	var m: String = str(f.mood_name)
	if m == "neutral" or int(f.mood_intensity) <= 0:
		return 1.0
	var sg: Dictionary = def_of(m).get("effects", {}).get("skill_gain", {})
	var inten: int = int(f.mood_intensity)
	var mult := 1.0
	if sg.has("*"):
		mult *= _scaled(float(sg["*"]), inten)
	if sg.has(skill):
		mult *= _scaled(float(sg[skill]), inten)
	elif (cfg().get("creative_skills", []) as Array).has(skill) and sg.has("creative"):
		mult *= _scaled(float(sg["creative"]), inten)
	return mult

## Bonus (or penalty) XP for the skills the finished interaction trains. Returns {skill: delta}.
static func on_finished(folk_id: int, iid: String, success: bool) -> Dictionary:
	var applied: Dictionary = {}
	var f = SysUtil.folk(folk_id)
	if f == null:
		return applied
	var d: Dictionary = SimEnv.data().interaction_def(iid)
	if success:
		var xp: Dictionary = d.get("skill_xp_per_min", {})
		var dur: float = float(d.get("duration_min", 10.0))
		for s in xp:
			var base: float = float(xp[s]) * dur
			var mult := skill_mult(f, str(s))
			if absf(mult - 1.0) < 0.005:
				continue
			var bonus := base * (mult - 1.0)
			if bonus > 0.0:
				f.add_skill_xp(str(s), bonus)
			elif f.skills.has(s):
				var sk: Dictionary = f.skills[s]
				var floor_xp: float = Folk.xp_for_level(int(sk["level"]))
				sk["xp"] = maxf(float(sk["xp"]) + bonus, floor_xp)
			applied[str(s)] = snappedf(bonus, 0.01)
		_imprint_peak(f, folk_id)
	_ctx_keys.erase(folk_id)
	return applied

# ------------------------------------------------------------------ contagion
static func _trait_mult(id: int, key: String, default_v: float = 1.0) -> float:
	var m := default_v
	for t in RelationshipService.traits_of(id):
		var td: Dictionary = SimEnv.data().trait_def(str(t))
		var sd: Dictionary = td.get("social", {})
		if sd.has(key):
			m *= float(sd[key])
	return m

static func susceptibility(dst, mood: String) -> float:
	var s := _trait_mult(int(dst.id), "contagion", 1.0)
	if valence(mood) < 0:
		for t in dst.traits:
			s *= float((cfg().get("contagion", {}).get("negative_resist", {}) as Dictionary).get(str(t), 1.0))
	return s

## One game minute of drift. Returns the number of folk who caught a mood (for tests / debug).
static func contagion_tick() -> int:
	var c: Dictionary = cfg().get("contagion", {})
	if not bool(c.get("enabled", true)):
		return 0
	var caught := 0
	var folks: Array = WorldIface.all_folk()
	var moods: Array = c.get("moods", [])
	var radius: float = float(c.get("radius", 4.5))
	var min_i: int = int(c.get("min_intensity", 2))
	var prefix: String = str(c.get("buff_prefix", "caught_"))
	for src in folks:
		if int(src.mood_intensity) < min_i or not moods.has(str(src.mood_name)) or SysUtil.is_away(src):
			continue
		var bid: String = prefix + str(src.mood_name)
		if SimEnv.data().buff_def(bid).is_empty():
			continue
		for dst in folks:
			if dst.id == src.id or SysUtil.is_away(dst) or dst.has_buff(bid):
				continue
			if str(dst.mood_name) == str(src.mood_name) and int(dst.mood_intensity) >= int(src.mood_intensity):
				continue
			var in_circle: bool = Conversation.same_circle(int(src.id), int(dst.id))
			if not in_circle and Vector2(dst.tile - src.tile).length() > radius:
				continue
			var p: float = float(c.get("chance_per_min", 0.035)) * (float(c.get("circle_mult", 3.0)) if in_circle else 1.0)
			p *= susceptibility(dst, str(src.mood_name)) * float(src.mood_intensity) / 2.0
			if SysUtil.rng.randf() < p:
				add_hidden(dst, bid)
				caught += 1
				SysUtil.game_event("mood_contagion", {"folk_id": int(dst.id), "target_id": int(src.id), "mood": str(src.mood_name)})
	return caught

# ------------------------------------------------------------------ emotional memory
static func area_key(tile: Vector2i) -> String:
	var sz: int = maxi(int(cfg().get("memory", {}).get("area_tile", 8)), 1)
	return "area:%d,%d" % [int(floor(float(tile.x) / sz)), int(floor(float(tile.y) / sz))]

static func imprint(f, key: String, value: float, kind: String, mood_name: String = "", text: String = "") -> void:
	if f == null or key == "":
		return
	f.remember(key, value)
	var cap: int = int(cfg().get("memory", {}).get("max_moments", 16))
	var arr: Array = moments.get(int(f.id), [])
	arr.append({"key": key, "v": snappedf(value, 0.01), "kind": kind, "day": SysUtil.day(), "mood": mood_name, "label": text, "t": SysUtil.now(), "last": -100000})
	while arr.size() > cap:
		arr.pop_front()
	moments[int(f.id)] = arr

## A strong shared moment (first kiss, breakup, wedding...) imprinted on both folk, tied to each other and to where it happened.
static func imprint_pair(a, b, value: float, kind: String, text: String = "") -> void:
	if a == null or b == null:
		return
	imprint(a, "folk:%d" % int(b.id), value, kind, "", text)
	imprint(b, "folk:%d" % int(a.id), value, kind, "", text)
	imprint(a, area_key(a.tile), value * 0.7, kind, "", text)
	imprint(b, area_key(a.tile), value * 0.7, kind, "", text)

static func _imprint_peak(f, folk_id: int) -> void:
	var inten: int = int(f.mood_intensity)
	var mc: Dictionary = cfg().get("memory", {})
	if inten < int(mc.get("strong_intensity", 3)):
		return
	var val: int = valence(str(f.mood_name))
	if val == 0:
		return
	var keys: Array = _ctx_keys.get(folk_id, [])
	var v: float = float(mc.get("value", 0.4)) * float(val)
	for k in keys:
		imprint(f, str(k), v, "mood_peak", str(f.mood_name))

## Called when an interaction begins: remember what it is tied to and trigger nostalgia / unease for old strong moments.
static func on_started(folk_id: int, iid: String, target_id: int) -> void:
	var f = SysUtil.folk(folk_id)
	if f == null:
		return
	var d: Dictionary = SimEnv.data().interaction_def(iid)
	var keys: Array = [area_key(f.tile)]
	match str(d.get("target", "object")):
		"object":
			keys.append("obj:%d" % target_id)
		"folk":
			keys.append("folk:%d" % target_id)
	_ctx_keys[folk_id] = keys
	check_nostalgia(f, keys)

static func check_nostalgia(f, keys: Array) -> String:
	var arr: Array = moments.get(int(f.id), [])
	if arr.is_empty():
		return ""
	var mc: Dictionary = cfg().get("memory", {})
	var now := SysUtil.now()
	for m in arr:
		if not keys.has(str(m["key"])) or absf(float(m["v"])) < 0.3:
			continue
		if now - int(m["t"]) < int(mc.get("nostalgia_min_age_min", 720)) or now - int(m["last"]) < int(mc.get("cooldown_min", 720)):
			continue
		m["last"] = now
		var pos: bool = float(m["v"]) > 0.0
		f.add_buff("nostalgic_glow" if pos else "uneasy_memory")
		var th: Array = mc.get("thoughts_pos" if pos else "thoughts_neg", [])
		if not th.is_empty():
			SimEnv.emit("thought", int(f.id), str(SysUtil.pick(th)))
		SysUtil.game_event("emotional_memory", {"folk_id": int(f.id), "key": str(m["key"]), "positive": pos, "kind": str(m["kind"])})
		return "nostalgic" if pos else "uneasy"
	return ""

static func moments_of(folk_id: int) -> Array:
	return (moments.get(folk_id, []) as Array).duplicate(true)

# ------------------------------------------------------------------ mood journal
static func record_minute(f) -> void:
	var fid: int = int(f.id)
	var mm: Dictionary = mood_minutes.get(fid, {})
	var m: String = str(f.mood_name)
	mm[m] = int(mm.get(m, 0)) + 1
	mood_minutes[fid] = mm
	if m != "neutral":
		var pk: Dictionary = peaks.get(fid, {"best": ["", 0], "worst": ["", 0]})
		var val := valence(m)
		var inten: int = int(f.mood_intensity)
		if val > 0 and inten > int(pk["best"][1]):
			pk["best"] = [m, inten]
		elif val < 0 and inten > int(pk["worst"][1]):
			pk["worst"] = [m, inten]
		peaks[fid] = pk

static func journal_for(fid: int) -> Dictionary:
	var mm: Dictionary = mood_minutes.get(fid, {})
	var total := 0
	var top := ""
	var top_v := 0
	for m in mm:
		total += int(mm[m])
		if int(mm[m]) > top_v:
			top_v = int(mm[m])
			top = str(m)
	var pk: Dictionary = peaks.get(fid, {"best": ["", 0], "worst": ["", 0]})
	return {"samples": total, "top": top, "top_pct": int(round(100.0 * top_v / maxf(total, 1.0))), "best": str(pk["best"][0]), "worst": str(pk["worst"][0])}

static func on_day(_day: int) -> Array:
	var jc: Dictionary = cfg().get("journal", {})
	var lines: Array = []
	if bool(jc.get("enabled", true)):
		for f in SysUtil.residents():
			var j := journal_for(int(f.id))
			if int(j["samples"]) < int(jc.get("min_samples", 120)):
				continue
			var s: String = "%s was mostly %s (%d%%)" % [f.name, label(str(j["top"])).to_lower(), int(j["top_pct"])]
			if str(j["best"]) != "":
				s += ", best: " + label(str(j["best"])).to_lower()
			if str(j["worst"]) != "":
				s += ", worst: " + label(str(j["worst"])).to_lower()
			lines.append(s)
	last_journal = lines
	mood_minutes.clear()
	peaks.clear()
	if not lines.is_empty():
		var shown: Array = lines.slice(0, int(jc.get("max_lines", 3)))
		SysUtil.notify("Mood journal: " + "; ".join(shown) + ".", str(jc.get("kind", "info")))
		SysUtil.game_event("mood_journal", {"lines": lines})
	return lines

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	var mo: Dictionary = {}
	for k in moments:
		mo[str(k)] = (moments[k] as Array).duplicate(true)
	return {"moments": mo, "last_journal": last_journal.duplicate()}

static func from_dict(d: Dictionary) -> void:
	reset()
	var mo: Dictionary = d.get("moments", {})
	for k in mo:
		var arr: Array = []
		for m in mo[k]:
			var e: Dictionary = (m as Dictionary).duplicate()
			e["day"] = int(e.get("day", 0))
			e["t"] = int(e.get("t", 0))
			e["last"] = int(e.get("last", -100000))
			e["v"] = float(e.get("v", 0.0))
			arr.append(e)
		moments[int(k)] = arr
	last_journal = (d.get("last_journal", []) as Array).duplicate()
