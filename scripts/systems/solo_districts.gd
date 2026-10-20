class_name SoloDistricts
extends RefCounted
## Districts of the town (R14): a district is a set of lots with a roughness 0..1. The Kiln Quarter (south-east, around the Works) is the rough one.
## Roughness is never read from heritage (R13). It starts from data/solo.json and moves with the town's own crime (monthly, `drift`).
## Everything here is a lookup of numbers in data/solo.json "districts" / "crime"; the incident systems multiply their own dice by `mult`.

static var rough: Dictionary = {}         # district id -> roughness now (starts from the data; saved in the solo block through SoloHome)

static func reset() -> void:
	rough = {}

static func districts() -> Dictionary:
	return SoloCfg.sect("districts")

## District id of a lot ("" = an ordinary lot).
static func district_of(lot_id: String) -> String:
	if lot_id == "":
		return ""
	var ds: Dictionary = districts()
	for id in ds:
		if lot_id in (ds[id] as Dictionary).get("lots", []):
			return str(id)
	return ""

static func roughness_of(district_id: String) -> float:
	if district_id == "":
		return 0.0
	return float(rough.get(district_id, (districts().get(district_id, {}) as Dictionary).get("roughness", 0.0)))

static func rough_at(lot_id: String) -> float:
	return roughness_of(district_of(lot_id))

static func label_of(district_id: String) -> String:
	return str((districts().get(district_id, {}) as Dictionary).get("label", district_id))

## Multiple of the town's rate of an incident kind (burglary | robbery | assault | petty) inside the lot's district. 1.0 outside every district.
## roughness 0.85 gives the multiple of the data; lower roughness scales it by (r / 0.85)^k, capped.
static func mult(lot_id: String, kind: String) -> float:
	var r: float = rough_at(lot_id)
	if r <= 0.0:
		return 1.0
	var c: Dictionary = SoloCfg.sect("crime")
	var m: float = float((c.get("multiples", {}) as Dictionary).get(kind, 1.0))
	var cap: float = float((c.get("caps", {}) as Dictionary).get(kind, m))
	var scale: float = pow(clampf(r / 0.85, 0.0, 1.5), float(c.get("k_exponent", 1.5)))
	return minf(1.0 + (m - 1.0) * scale, cap)

## `mult` scaled by the "Gang violence" setting (off / low / normal / high) for the violent kinds; the property kinds ignore it.
static func violence_mult(lot_id: String, kind: String) -> float:
	var m: float = mult(lot_id, kind)
	if kind in ["robbery", "assault"]:
		m = 1.0 + (m - 1.0) * setting_factor()
	return m

static func setting_factor() -> float:
	var table: Dictionary = (SoloCfg.sect("crime") as Dictionary).get("violence_setting", {})
	var key: String = str(GameSettings.get_str("gang_violence"))
	if key == "":
		key = "normal"
	var f: float = float(table.get(key, 1.0))
	if f > 0.0 and not GameSettings.get_bool("mature_events"):
		f = minf(f, float(table.get("low", 0.35)))
	return f
