class_name RelationshipRomance
extends RefCounted
## Trust, tension, bond tracks, romance stages, dating and breakups.

# ------------------------------------------------------------------ social depth: trust / tension / knowledge / secrets / romance
static func _sub(p: Dictionary, key: String, default: Variant) -> Variant:
	if not p.has(key):
		p[key] = default
	return p[key]

## Trait conflicts / affinities (data/traits.json) feed compatibility on top of the social.json pair table.
static func _trait_social_compat(a: int, b: int) -> float:
	var total: float = 0.0
	var data = SimEnv.data()
	for x in RelationshipBits.traits_of(a):
		var xd: Dictionary = data.trait_def(str(x))
		for y in RelationshipBits.traits_of(b):
			var yd: Dictionary = data.trait_def(str(y))
			if (xd.get("conflicts", []) as Array).has(str(y)) or (yd.get("conflicts", []) as Array).has(str(x)):
				total -= 0.4
			if (xd.get("affinities", []) as Array).has(str(y)) or (yd.get("affinities", []) as Array).has(str(x)):
				total += 0.35
	return total

static func tension(a: int, b: int) -> float:
	return RelationshipService.value(a, b, "tension")

static func add_tension(a: int, b: int, delta: float) -> void:
	var v: float = clampf(RelationshipService.value(a, b, "tension") + delta, 0.0, 100.0)
	RelationshipService.set_value(a, b, "tension", v)
	if v >= float(RelationshipService.cfg().get("arguments", {}).get("resolve_below", 10)) * 2.0:
		RelationshipService._pair(a, b)["heated"] = true

static func trust(a: int, b: int) -> float:
	return RelationshipService.value(a, b, "trust")

## Keep the directional `bond` / `ex` status tracks in step with the pair flags.
static func _update_bond_tracks(a: int, b: int) -> void:
	var p: Dictionary = RelationshipService._pair(a, b)
	var fl: Dictionary = p["flags"]
	var rank: float = 0.0
	if fl.get("spouse", false):
		rank = 4.0
	elif fl.get("partner", false):
		rank = 3.0
	elif fl.get("sweetheart", false):
		rank = 2.0
	elif fl.get("dating", false):
		rank = 1.0
	var ex: float = 1.0 if fl.get("ex", false) else 0.0
	for dir in [[a, b], [b, a]]:
		if not is_equal_approx(RelationshipService.value(dir[0], dir[1], "bond"), rank):
			RelationshipService.set_value(dir[0], dir[1], "bond", rank)
		if not is_equal_approx(RelationshipService.value(dir[0], dir[1], "ex"), ex):
			RelationshipService.set_value(dir[0], dir[1], "ex", ex)

## Folk `a` is romantically attached to (spouse / partner / sweetheart / dating). romantic_partners() keeps its old meaning.
static func exclusive_partners(a: int) -> Array:
	var out: Array = []
	for key in RelationshipService.pairs:
		var p: Dictionary = RelationshipService.pairs[key]
		var other: int = -1
		if int(p["lo"]) == a:
			other = int(p["hi"])
		elif int(p["hi"]) == a:
			other = int(p["lo"])
		if other < 0:
			continue
		var fl: Dictionary = p["flags"]
		if fl.get("spouse", false) or fl.get("partner", false) or fl.get("sweetheart", false) or fl.get("dating", false):
			out.append(other)
	return out

static func is_ex(a: int, b: int) -> bool:
	return RelationshipBits.has_flag(a, b, "ex")

## State machine for a pair's romance: none -> crush -> flirting -> dating -> sweethearts -> partners -> engaged -> married,
## with `ex` after a breakup. Symmetric (uses the weaker side for flirting).
static func romance_stage(a: int, b: int) -> String:
	var p: Dictionary = RelationshipService._pair(a, b, false)
	var rc: Dictionary = RelationshipService.cfg().get("romance", {})
	if not p.is_empty():
		var fl: Dictionary = p["flags"]
		if fl.get("spouse", false):
			return "married"
		if FamilyTree.fiance_of(a) == b:
			return "engaged"
		if fl.get("partner", false):
			return "partners"
		if fl.get("sweetheart", false):
			return "sweethearts"
		if fl.get("dating", false):
			return "dating"
		if fl.get("ex", false):
			return "ex"
	var r1: float = RelationshipService.value(a, b, "romance")
	var r2: float = RelationshipService.value(b, a, "romance")
	if maxf(r1, r2) < float(rc.get("crush_min", 20)):
		return "none"
	if minf(r1, r2) >= float(rc.get("crush_min", 20)) and maxf(r1, r2) >= float(rc.get("flirt_min", 30)):
		return "flirting"
	return "crush"

static func stage_label(stage: String) -> String:
	return {"none": "No spark yet", "crush": "Crush", "flirting": "Flirting", "dating": "Dating", "sweethearts": "Sweethearts", "partners": "Partners",
		"engaged": "Engaged", "married": "Married", "ex": "Exes"}.get(stage, stage.capitalize())

## Chemistry 0..1: a stable per-pair roll nudged by trait compatibility. Romantic interactions use it as a bonus / penalty.
static func spark(a: int, b: int) -> float:
	var lo: int = mini(a, b)
	var hi: int = maxi(a, b)
	var h: int = posmod(lo * 73856093 ^ hi * 19349663, 1000)
	var roll: float = float(h) / 999.0
	return clampf(0.5 + RelationshipBits.compatibility(a, b) * 0.35 + (roll - 0.5) * 0.5, 0.0, 1.0)

static func spark_hearts(a: int, b: int) -> String:
	var n: int = int(round(spark(a, b) * 5.0))
	return "♥".repeat(n) + "♡".repeat(5 - n)

static func start_dating(a: int, b: int, announce: bool = true) -> void:
	RelationshipBits.set_flag(a, b, "dating", true, announce)
	var p: Dictionary = RelationshipService._pair(a, b)
	if not p.has("dates"):
		p["dates"] = 0

static func dates_count(a: int, b: int) -> int:
	return int(RelationshipService._pair(a, b, false).get("dates", 0))

## End a dating / sweetheart / partner relationship (spouses must divorce). Returns false when there is nothing to end.
static func breakup(initiator: int, other: int, cause: String = "breakup", severity: float = 1.0) -> bool:
	var p: Dictionary = RelationshipService._pair(initiator, other, false)
	if p.is_empty():
		return false
	var fl: Dictionary = p["flags"]
	if fl.get("spouse", false) or not (fl.get("partner", false) or fl.get("sweetheart", false) or fl.get("dating", false)):
		return false
	var rc: Dictionary = RelationshipService.cfg().get("romance", {})
	RelationshipBits.set_flag(initiator, other, "ex", true, false)
	var cap: float = float(rc.get("breakup_romance_cap", 5))
	for dir in [[initiator, other], [other, initiator]]:
		if RelationshipService.value(dir[0], dir[1], "romance") > cap:
			RelationshipService.set_value(dir[0], dir[1], "romance", cap)
	p["dates"] = 0
	RelationshipService.add_history(initiator, other, "break_up", -1.0, initiator)
	var fi = SysUtil.folk(initiator)
	var fo = SysUtil.folk(other)
	if cause == "cheating":
		if fi != null:
			fi.add_buff("heartbroken")
		if fo != null:
			fo.add_buff("guilty_pang")
	SysUtil.notify("%s and %s broke up%s." % [SysUtil.folk_name(initiator), SysUtil.folk_name(other), " (cheating)" if cause == "cheating" else ""], "relationship")
	SysUtil.game_event("breakup", {"folk_id": initiator, "target_id": other, "cause": cause, "severity": severity})
	if fi != null and fo != null:
		Emotions.imprint_pair(fi, fo, -0.5 * minf(severity, 1.4), "breakup", "the breakup")
	return true

## Mark the last shared-history entry with the outcome tier / label of the interaction that just ran.
static func _tag_last_history(a: int, b: int, tier: String, text: String) -> void:
	var p: Dictionary = RelationshipService._pair(a, b, false)
	if p.is_empty() or (p["history"] as Array).is_empty():
		return
	var ev: Dictionary = (p["history"] as Array).back()
	if tier != "":
		ev["tier"] = tier
	if text != "":
		ev["label"] = text
