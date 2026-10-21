class_name WearRules
extends RefCounted
## Task 41a (view only, pure functions; no sim state, no rng): the rules of the wear / poverty layer. Data: data/wear_layer.json (poverty tiers, mess levels and
## clutter tables, wall grime) and data/district_dressing.json ("presets", "districts", "wear_map": what a district wear level 0..1 turns into dressing density).
##   poverty_score(funds)     0 (comfortable) .. 1 (broke) from a household's funds
##   tier_of(score)           "poor" | "modest" | "comfortable"
##   pick_of(object_id)       0..2, stable, so a poor flat has mismatched pieces
##   mess_level(per_tile)     "tidy" | "untidy" | "messy" | "squalid" for a room's mess per tile
##   clutter_for_tile(...)    deterministic clutter pieces for one tile: [{kind, ox, oz, yaw, scale, tone}]
##   density(key, wear)       linear value of a wear_map entry at a district wear level

const PATH := "res://data/wear_layer.json"
const DRESS_PATH := "res://data/district_dressing.json"
static var _cfg: Dictionary = {}
static var _dress: Dictionary = {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = _load(PATH)
	return _cfg


static func dressing_cfg() -> Dictionary:
	if _dress.is_empty():
		_dress = _load(DRESS_PATH)
	return _dress


static func _load(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


# ------------------------------------------------------------------ poverty

static func poverty_score(funds: int) -> float:
	var p: Dictionary = cfg().get("poverty", {})
	var lo := float(p.get("poor_funds", 900))
	var hi := float(p.get("comfy_funds", 9000))
	return clampf(1.0 - (float(funds) - lo) / maxf(hi - lo, 1.0), 0.0, 1.0)


static func tier_of(score: float) -> String:
	for t in (cfg().get("poverty", {}) as Dictionary).get("tiers", []):
		if score >= float(t["min"]):
			return str(t["id"])
	return "comfortable"


static func pick_of(object_id: int) -> int:
	var h: int = (object_id * 2654435761) & 0x7FFFFFFF
	return (h >> 8) % 3


# ------------------------------------------------------------------ mess

static func mess_level(per_tile: float) -> String:
	var out := "tidy"
	for l in (cfg().get("mess", {}) as Dictionary).get("levels", []):
		if per_tile >= float(l["min"]):
			out = str(l["id"])
	return out


static func hash01(x: int, y: int, salt: int) -> float:
	var h: int = (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0


## How many clutter pieces a tile with this mess shows (0 when tidy). More mess = more pieces, never random: the same mess always gives the same pieces.
static func clutter_count(mess: float) -> int:
	var m: Dictionary = cfg().get("mess", {})
	var lv := ["tidy", "untidy", "messy", "squalid"].find(mess_level(mess))
	var per: Array = m.get("props_per_level", [0, 1, 2, 4])
	return mini(int(per[clampi(lv, 0, per.size() - 1)]), int(m.get("max_per_tile", 4)))


## Pieces for one tile: kind by room type, position / yaw / size / colour tone by tile hash. `poverty` adds a few boxes and bags even in a tidy room.
static func clutter_for_tile(t: Vector2i, mess: float, room_kind: String, poverty: float) -> Array:
	var m: Dictionary = cfg().get("mess", {})
	var n := clutter_count(mess)
	var kinds: Array = (m.get("kinds_by_room", {}) as Dictionary).get(room_kind, (m.get("kinds_by_room", {}) as Dictionary).get("default", ["box"]))
	var out: Array = []
	for i in n:
		out.append(_piece(t, i, kinds[int(hash01(t.x, t.y, 31 + i) * kinds.size()) % kinds.size()]))
	var base: Dictionary = m.get("poverty_baseline", {})
	if n == 0 and poverty >= float(base.get("min_poverty", 0.6)) and hash01(t.x, t.y, 47) < float(base.get("chance", 0.07)) * poverty:
		var bk: Array = base.get("kinds", ["box"])
		out.append(_piece(t, 9, bk[int(hash01(t.x, t.y, 48) * bk.size()) % bk.size()]))
	return out


static func _piece(t: Vector2i, i: int, kind: String) -> Dictionary:
	return {"kind": kind, "ox": hash01(t.x, t.y, 51 + i) * 0.7 + 0.15, "oz": hash01(t.x, t.y, 61 + i) * 0.7 + 0.15, "yaw": hash01(t.x, t.y, 71 + i) * 360.0,
		"scale": 0.85 + hash01(t.x, t.y, 81 + i) * 0.4, "tone": hash01(t.x, t.y, 91 + i)}


# ------------------------------------------------------------------ districts

static func preset(id: String) -> Dictionary:
	return (dressing_cfg().get("presets", {}) as Dictionary).get(id, {})


## The wear level of a lot: its district's declared level (`wear` or its preset's), else -1 (the lot declares none).
static func district_wear_of_lot(lot_id: String) -> float:
	for d in dressing_cfg().get("districts", []):
		if lot_id in (d.get("lots", []) as Array):
			return float(d["wear"]) if d.has("wear") else float(preset(str(d.get("preset", ""))).get("wear", -1.0))
	return -1.0


## wear_map entry [value at wear 0, value at wear 1] interpolated; 0 below the entry's `min_wear`.
static func density(key: String, wear: float) -> float:
	var e: Variant = (dressing_cfg().get("wear_map", {}) as Dictionary).get(key, null)
	if e is Dictionary:
		if wear < float(e.get("min_wear", 0.0)):
			return 0.0
		var r: Array = e.get("range", [0.0, 1.0])
		return lerpf(float(r[0]), float(r[1]), clampf(wear, 0.0, 1.0))
	if e is Array:
		return lerpf(float(e[0]), float(e[1]), clampf(wear, 0.0, 1.0))
	return 0.0


## Wall grime strength 0..1 for a wall edge: the lot's wear / poverty, strong on the outside, lighter indoors.
static func wall_wear(lot_wear: float, exterior: bool) -> float:
	var w: Dictionary = cfg().get("wall", {})
	var base := float(w.get("base", 0.1))
	var mult := float(w.get("exterior_mult", 1.0)) if exterior else float(w.get("interior_mult", 0.55))
	return clampf(base + maxf(lot_wear, 0.0) * mult, 0.0, 1.0)
