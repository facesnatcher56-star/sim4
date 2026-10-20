class_name HomeBare
extends RefCounted
## How bare is a household's home (task 32f)? 0 = enough to do for everyone, 1 = nothing to do at home. Counts the objects on the home lot that
## advertise something (beds, fridges, seats, tvs ...) against `bare.usable_per_folk` per resident; lights, doors, windows and the yard's fixed
## pieces do not count. Used to send folk out more (PlaceAutoPlan, DynPlans, DynSocial: park, cafe, friends) and to make daydreaming at home less
## attractive (`mult`, from Autonomy). Only for households a player has (or could have): townies and stub worlds answer 0, so nothing else changes.
## Data: data/dynamic_life.json `bare`. Not saved: a pure function of the world, cached until the next game hour or the next object change.

static var _cache: Dictionary = {}     # "hid" -> [hour stamp, factor]

static func cfg() -> Dictionary:
	return DynLife.cfg().get("bare", {})

static func reset() -> void:
	_cache.clear()

static func _counts(def_id: String) -> bool:
	var d: Dictionary = SimEnv.data().object_def(def_id)
	if d.is_empty() or (d.get("advertises", {}) as Dictionary).is_empty() or str(d.get("mount", "")) != "":
		return false
	var skip: Array = StartHome.cfg().get("keep_defs", [])
	if skip.has(def_id):
		return false
	for t in d.get("tags", []):
		if str(t) in ["structure", "door", "window", "ceiling"]:
			return false
	return true

static func _folk_count(hid: int) -> int:
	var n: int = 0
	for f in SysUtil.residents():
		if int(f.household_id) == hid and str(f.age_stage) != "baby":
			n += 1
	return maxi(n, 1)

## Bare factor of the household's home, 0..1 (0 when it is not a player household or there is no home lot to look at).
static func factor_of(hid: int) -> float:
	var c: Dictionary = cfg()
	if c.is_empty() or hid <= 0 or not bool(c.get("enabled", true)):
		return 0.0
	var w = WorldIface.world()
	var stamp: int = SysUtil.now() / 60 * 1000003 + (int(w.get("obj_gen")) if w != null and w.get("obj_gen") != null else 0)       # an hour, or any object placed / removed since
	var hit: Array = _cache.get(hid, [])
	if not hit.is_empty() and int(hit[0]) == stamp:
		return float(hit[1])
	var out: float = _compute(hid, c)
	_cache[hid] = [stamp, out]
	return out

static func _compute(hid: int, c: Dictionary) -> float:
	var played: bool = Players.player_of(hid) >= 0 or (Players.table.is_empty() and hid == Economy.primary_household())
	if not played or WorldIface.world() == null:
		return 0.0
	var rc: Rect2i = NeighborhoodLots.rect_of(PlayerLots.home_of_household(hid))
	if rc.size.x <= 0:
		return 0.0
	var n: int = 0
	for o in SysUtil.all_world_objects():
		if rc.has_point(o.tile) and _counts(str(o.def_id)):
			n += 1
	var want: float = float(_folk_count(hid)) * float(c.get("usable_per_folk", 6))
	return clampf(1.0 - float(n) / want, 0.0, 1.0)

static func factor(f) -> float:
	return 0.0 if f == null else factor_of(int(f.household_id))

## 1 + gain x bare: the factor on the chance of going out / seeing a friend.
static func boost(f, key: String) -> float:
	var b: float = factor(f)
	return 1.0 if b <= 0.0 else 1.0 + b * float(cfg().get(key, 0.0))

## The urgency above which a need stops the idle fillers (3 in a furnished home; `idle_urgency` in a bare one, where the fix is not at hand).
static func idle_urgency(f) -> float:
	return float(cfg().get("idle_urgency", 3.0)) if is_thin(f) else 3.0

## Under-furnished enough that needs may go unmet at home (`thin_at`, 0.25 of the way to bare).
static func is_thin(f) -> bool:
	return factor(f) >= float(cfg().get("thin_at", 0.25))

## Autonomy: daydreaming (and the idle fillers) lose their appeal in a home with little in it. 1 = unchanged.
static func autonomy_mult(f, iid: String, d: Dictionary) -> float:
	var c: Dictionary = cfg()
	var key: String = ""
	if iid == "daydream":
		key = "daydream_mult"
	elif (d.get("tags", []) as Array).has("idle_life"):
		key = "idle_life_mult"
	if key == "":
		return 1.0
	var b: float = factor(f)
	return 1.0 if b <= 0.0 else lerpf(1.0, float(c.get(key, 1.0)), b)
