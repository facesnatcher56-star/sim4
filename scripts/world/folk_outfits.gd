class_name FolkOutfits
extends RefCounted
## Role outfits for staff / NPCs (data/outfits.json): barista apron, trainer sportswear, librarian cardigan + glasses, student
## uniforms, office wear ... Only clothes and accessories are set; the person underneath (skin, hair, face, body) stays random
## and every outfit still goes through the no-clones rule (GeneticsUnique).

static var _cfg: Dictionary = {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var txt := FileAccess.get_file_as_string("res://data/outfits.json")
		var parsed: Variant = JSON.parse_string(txt)
		_cfg = parsed if parsed is Dictionary else {"roles": {}}
	return _cfg


static func has_role(role: String) -> bool:
	return (cfg().get("roles", {}) as Dictionary).has(role)


## Role for a townie: career first, else by age stage (students), else "" (casual clothes).
static func role_for(career: String, stage: String) -> String:
	var cr: Dictionary = cfg().get("career_roles", {})
	if career != "" and cr.has(career):
		return str(cr[career])
	return str((cfg().get("stage_roles", {}) as Dictionary).get(stage, ""))


static func _pick(arr: Array, g: RandomNumberGenerator, def):
	return def if arr.is_empty() else arr[g.randi_range(0, arr.size() - 1)]


## Dress `ap` for `role` (returns a modified copy; unknown role = unchanged copy).
static func apply_role(ap: Dictionary, role: String, g: RandomNumberGenerator) -> Dictionary:
	var out: Dictionary = ap.duplicate(true)
	var d: Dictionary = (cfg().get("roles", {}) as Dictionary).get(role, {})
	if d.is_empty():
		return out
	for k in ["top", "bottom", "shoes", "hat", "glasses", "bag", "scarf"]:
		if d.has(k):
			out[k] = int(_pick(d[k], g, out.get(k, 0)))
	for k2 in [["shirt", "shirt"], ["pants", "pants"], ["accent", "accent"]]:
		if d.has(k2[0]):
			out[k2[1]] = str(_pick(d[k2[0]], g, out.get(k2[1], "#808080")))
	out["color"] = out["shirt"]
	if int(out["top"]) == 4:
		out["bottom"] = 0
	if int(out["hat"]) > 0 and Genetics.HAT_BLOCK.has(int(out["hair_style"])):
		out["hat"] = 0
	return out


## Distinct role look: random people dressed for `role` until none clones anyone in `others`.
static func for_role(role: String, others: Array, g: RandomNumberGenerator) -> Dictionary:
	var chs: Array = GeneticsUnique._channels_of(others)
	var best: Dictionary = {}
	var bd := -1.0
	for _t in GeneticsUnique.tries():
		var cand: Dictionary = apply_role(Genetics.random_appearance(g), role, g)
		var d: float = GeneticsUnique.min_distance(cand, chs)
		if d >= GeneticsUnique.threshold():
			return cand
		if d > bd:
			bd = d
			best = cand
	return best


## Re-dress an existing appearance for a role (keeps the person), staying distinct from `others`.
static func dress(ap: Dictionary, role: String, others: Array, g: RandomNumberGenerator) -> Dictionary:
	var chs: Array = GeneticsUnique._channels_of(others)
	var best: Dictionary = apply_role(ap, role, g)
	var bd: float = GeneticsUnique.min_distance(best, chs)
	for _t in GeneticsUnique.tries():
		if bd >= GeneticsUnique.threshold():
			break
		var cand: Dictionary = apply_role(ap, role, g)
		if _t > 10:
			cand["hair_style"] = g.randi_range(0, 15)
		var d: float = GeneticsUnique.min_distance(cand, chs)
		if d > bd:
			bd = d
			best = cand
	return best
