class_name SoloDistricts
extends RefCounted
## Districts of the town (R14): a district is a set of lots with a roughness 0..1. The Kiln Quarter (south-east, around the Works) is the rough one.
## Roughness is never read from heritage (R13). It starts from data/solo.json and moves with the town's own crime (monthly, `drift`).
## Everything here is a lookup of numbers in data/solo.json "districts" / "crime"; the incident systems multiply their own dice by `mult`.

static var rough: Dictionary = {}         # district id -> roughness now (starts from the data; saved in the solo block through SoloHome)

static func reset() -> void:
	rough = {}

## Monthly (every `pressure.drift_days` days): roughness follows the town's own crime and the police budget, never heritage. A crime wave pushes
## it up, a quiet well-policed month eases it, so a district can recover or decay.
static func on_day(day: int) -> void:
	if not SoloHome.active:
		return
	var every: int = int((SoloCfg.sect("pressure") as Dictionary).get("drift_days", 28))
	if every <= 0 or day % every != 0:
		return
	var pressure: float = CrimeRate.crime_mult() - 1.0           # 0.6 .. 1.8 around 1.0
	for id in districts():
		var r: float = roughness_of(str(id))
		var base: float = float((districts()[id] as Dictionary).get("roughness", 0.5))
		r += 0.04 * pressure + 0.02 * (base - r)                 # crime pushes it, the district's history pulls it back
		rough[str(id)] = clampf(r, 0.25, 1.0)

static func districts() -> Dictionary:
	return SoloCfg.sect("districts")

## District id of a lot ("" = an ordinary lot).
static func district_of(lot_id: String) -> String:
	if lot_id == "":
		return ""
	var phys: String = str(SoloHome.phys.get(lot_id, lot_id))          # a role swap (moving house) changes labels, not buildings
	var ds: Dictionary = districts()
	for id in ds:
		if phys in (ds[id] as Dictionary).get("lots", []):
			return str(id)
	return ""

## The district around a tile: a lot of the district, or the street / park tiles within MARGIN tiles of the district's lots ("" = none).
const MARGIN := 7

static func district_at_tile(tile: Vector2i) -> String:
	var lot: String = NeighborhoodLots.lot_at(tile)
	if lot != "":
		return district_of(lot)
	var ds: Dictionary = districts()
	for id in ds:
		var box: Rect2i = Rect2i()
		var first := true
		for l in (ds[id] as Dictionary).get("lots", []):
			var rc: Rect2i = NeighborhoodLots.rect_of(SoloHome.label_of_phys(str(l)))
			if rc.size == Vector2i.ZERO:
				continue
			box = rc if first else box.merge(rc)
			first = false
		if not first and box.grow(MARGIN).has_point(tile):
			return str(id)
	return ""

## Lot id of a townie home number (Story's `lot` field), the same spread Neighborhood.residents_of uses.
static func townie_lot_id(n: int) -> String:
	var homes: Array = []
	for l in Neighborhood.lots():
		if str(l.get("type", "")) == "townie_home" and not PlayerLots.is_claimed(str(l["id"])):
			homes.append(str(l["id"]))
	return "" if homes.is_empty() else str(homes[(n - 1) % homes.size()])

## District of an incident subject (a folk where they stand, a household lot, a townie lot).
static func district_of_subject(subj) -> String:
	if subj == null:
		return ""
	if subj.folk != null:
		return district_at_tile(subj.folk.tile)
	var key: String = str(subj.lot_key)
	if key.begins_with("home:"):
		return district_of(PlayerLots.home_of_household(int(key.get_slice(":", 1))))
	if key.begins_with("town:"):
		return district_of(townie_lot_id(int(key.get_slice(":", 1))))
	return ""

## Factor on an incident's yearly rate inside its district (def key "district" = the crime kind; "" = unaffected).
static func rate_mult(def: Dictionary, subj) -> float:
	var kind: String = str(def.get("district", ""))
	if kind == "" or not SoloHome.active:
		return 1.0
	var d: String = district_of_subject(subj)
	return 1.0 if d == "" else mult_in(d, kind)

## Largest factor any district can give (the bound of the rejection sampling in IncidentRisk.max_rate).
static func max_mult(def: Dictionary) -> float:
	var kind: String = str(def.get("district", ""))
	if kind == "" or not SoloHome.active:
		return 1.0
	return maxf(float(((SoloCfg.sect("crime") as Dictionary).get("caps", {}) as Dictionary).get(kind, 1.0)), 1.0)

static func mult_in(district_id: String, kind: String) -> float:
	var r: float = roughness_of(district_id)
	if r <= 0.0:
		return 1.0
	var c: Dictionary = SoloCfg.sect("crime")
	var m: float = float((c.get("multiples", {}) as Dictionary).get(kind, 1.0))
	var cap: float = float((c.get("caps", {}) as Dictionary).get(kind, m))
	var out: float = minf(1.0 + (m - 1.0) * pow(clampf(r / 0.85, 0.0, 1.5), float(c.get("k_exponent", 1.5))), cap)
	if kind in ["robbery", "assault"]:
		out = 1.0 + (out - 1.0) * setting_factor()
	return out

## District of a case: where it happened (a household lot, a townie lot, or the victim's tile).
static func district_of_case(c: Dictionary) -> String:
	var scene: String = str(c.get("scene", ""))
	if scene.begins_with("home:"):
		return district_of(PlayerLots.home_of_household(int(scene.get_slice(":", 1))))
	if scene.begins_with("town:"):
		return district_of(townie_lot_id(int(scene.get_slice(":", 1))))
	var v = SysUtil.folk(int(c.get("victim", -1)))
	return district_at_tile(v.tile) if v != null else ""

## Police response in minutes for a case in a district: the district's own range replaces the town's (scaled by how rough it is).
static func police_delay(c: Dictionary, delay: int) -> int:
	if not SoloHome.active:
		return delay
	var d: String = district_of_case(c)
	if d == "" or roughness_of(d) <= 0.0:
		return delay
	var rg: Array = (districts().get(d, {}) as Dictionary).get("response_min", [35, 90])
	var span: int = int(rg[1]) - int(rg[0])
	return maxi(delay, int(rg[0]) + JusticeState.rng.randi_range(0, maxi(span, 0)))

## Factor on the on-scene catch chance (catch_on_scene 0.2 against the town's 0.5 in a rough district).
static func catch_factor(c: Dictionary) -> float:
	if not SoloHome.active:
		return 1.0
	var d: String = district_of_case(c)
	if d == "" or roughness_of(d) <= 0.0:
		return 1.0
	return float((districts().get(d, {}) as Dictionary).get("catch_on_scene", 0.2)) / 0.5

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
	return mult_in(district_of(lot_id), kind)

## The same with the "Gang violence" setting applied to the violent kinds (mult_in already does).
static func violence_mult(lot_id: String, kind: String) -> float:
	return mult_in(district_of(lot_id), kind)

static func setting_factor() -> float:
	var table: Dictionary = (SoloCfg.sect("crime") as Dictionary).get("violence_setting", {})
	var key: String = str(GameSettings.get_str("gang_violence"))
	if key == "":
		key = "normal"
	var f: float = float(table.get(key, 1.0))
	if f > 0.0 and not GameSettings.get_bool("mature_events"):
		f = minf(f, float(table.get("low", 0.35)))
	return f
