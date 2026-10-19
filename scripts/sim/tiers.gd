class_name Tiers
extends RefCounted
## LEVEL OF DETAIL for people (task 17.3). Every person is in exactly one tier:
##   ACTIVE       visible / near the controlled household(s): full sim, every minute.
##   NEAR         same area, off screen: full sim at a coarser cadence (near_period 5 min, far_near_period 10 min, elapsed minutes applied).
##   TOWN         elsewhere: cheap schedule-driven record (TownSim: where / doing what by the hour, needs as curves); in the world only as a rare leftover (town_period).
##   STATISTICAL  far or no recent contact: only the daily dice of Story / Away / Incidents.
## Which people are tiered by distance: the ambient population (crowd customers, coworkers and staff NPCs: meta crowd / staff). Everybody else in the world
## (household members, visitors, responders, burglars, ...) is simulated in full and counts as ACTIVE. Townie records without a Folk are TOWN or STATISTICAL
## (TownSim). The anchors are the non-away folk of every controlled household (the `Players` table) and the camera focus; with no anchor everybody is ACTIVE.
## Rules: promote at once, demote after demote_min minutes below (hysteresis, no flapping); at most active_cap ACTIVE (controlled folk first, the rest by
## distance with stickiness, the surplus is NEAR). No randomness. The sets (TierSets) change only on assignments; systems loop `Tiers.set_of(tier)`.
## Cadence: SimScheduler row "Tiers" (minute, order 90, before SimDirector). Cost: O(folk in the world), bounded by the cap on the crowd, plus a cached
## classification that is recomputed only when a person or an anchor moved. Saved in the "tiers" block (hysteresis continues after a load).
## Tier behaviour of every system: docs/PERFORMANCE.md "What every system declares".

const ACTIVE := 0
const NEAR := 1
const TOWN := 2
const STATISTICAL := 3
const NAMES := ["ACTIVE", "NEAR", "TOWN", "STATISTICAL"]

static var _sets := TierSets.new()
static var _world: Dictionary = {}         # id -> Folk: everybody in the world (maintained by on_added / on_removed)
static var _kind: Dictionary = {}          # id -> 0 simulated in full, 1 tiered by distance
static var _new: Dictionary = {}           # ids not classified yet (assigned directly, no hysteresis)
static var _below: Dictionary = {}         # id -> first minute the person qualified only for a lower tier
static var _cand: Dictionary = {}          # id -> [tier, distance, tile.x, tile.y, anchor signature]
static var _saved: Dictionary = {}         # tier map from a save, used by the first classification
static var _focus: Vector2i = Vector2i.ZERO
static var _has_focus := false
static var _listeners: Array = []          # Callable(id, old_tier, new_tier, folk)
static var _anchor_sig: int = 0
static var anchors: Array = []             # [{tile, lot}] of the last refresh
static var controlled_ids: Array = []      # folk ids of the controlled households' non-away members (last refresh)
static var stats: Dictionary = {}

static func reset() -> void:
	_sets.clear()
	_world.clear()
	_kind.clear()
	_new.clear()
	_below.clear()
	_cand.clear()
	_saved.clear()
	_has_focus = false
	anchors = []
	controlled_ids = []
	_anchor_sig = 0
	InterestArea.reset()
	TownSim.reset()
	stats = {"refresh": 0, "usec": 0, "changes": 0, "promotions": 0, "demotions": 0, "capped": 0, "resyncs": 0, "classified": 0, "reused": 0}

static func cfg() -> Dictionary:
	return SysUtil.table("tiers")

static func _n(key: String, d: int) -> int:
	return int(cfg().get(key, d))

# ------------------------------------------------------------------ API
## Tier of a Folk or of a person id (townie records: TownSim).
static func of(x) -> int:
	var id: int = int(x.id) if x is Folk else int(x)
	if _sets.tier_of.has(id):
		return int(_sets.tier_of[id])
	return TownSim.tier_of(id)

static func set_of(tier: int) -> Dictionary:
	return _sets.sets[tier]

static func active() -> Array:
	return (_sets.sets[ACTIVE] as Dictionary).values()

static func near() -> Array:
	return (_sets.sets[NEAR] as Dictionary).values()

static func town() -> Array:
	return (_sets.sets[TOWN] as Dictionary).keys() + TownSim.ids(TOWN)

static func statistical() -> Array:
	return TownSim.ids(STATISTICAL)

## [active, near, town, statistical] over the folk in the world AND the townie records.
static func counts() -> Array:
	return [_sets.count(ACTIVE), _sets.count(NEAR), _sets.count(TOWN) + TownSim.count(TOWN), TownSim.count(STATISTICAL)]

static func in_world_count() -> int:
	return _world.size()

## Minutes between full ticks of a person in the world: 1 for ACTIVE, near_period / far_near_period for NEAR, town_period for TOWN.
static func period_of(id: int) -> int:
	match int(_sets.tier_of.get(id, ACTIVE)):
		ACTIVE:
			return 1
		NEAR:
			var cd: Array = _cand.get(id, [])
			return _n("far_near_period", 10) if (cd.size() > 1 and int(cd[1]) >= _n("far_near_dist", 44)) else _n("near_period", 5)
		_:
			return _n("town_period", 15)

static func is_tiered(id: int) -> bool:
	return int(_kind.get(id, 0)) == 1

## True when this tiered person (a stranger) is due for a full tick at game tick `tick`: spread over the minutes by id.
static func due(id: int, tick: int) -> bool:
	var p: int = period_of(id)
	return p <= 1 or (tick + id) % p == 0

static func add_listener(c: Callable) -> void:
	if not _listeners.has(c):
		_listeners.append(c)

static func set_focus(tile: Vector2i) -> void:
	_focus = tile
	_has_focus = true

static func clear_focus() -> void:
	_has_focus = false

static func focus_tile() -> Vector2i:
	return _focus

# ------------------------------------------------------------------ world membership (hooks from World / StubWorld add_folk / remove_folk)
static func on_added(f) -> void:
	var id: int = int(f.id)
	_world[id] = f
	_new[id] = true
	_kind.erase(id)
	_cand.erase(id)
	if not _sets.has(id):
		_sets.put(id, ACTIVE, f)          # until the next refresh classifies it
	else:
		(_sets.sets[_sets.tier_of[id]] as Dictionary)[id] = f

static func on_removed(id: int) -> void:
	_world.erase(id)
	_kind.erase(id)
	_new.erase(id)
	_below.erase(id)
	_cand.erase(id)
	if _sets.has(id):
		var old: int = _sets.drop(id)
		_notify(id, old, -1, null)

static func _notify(id: int, old: int, new_t: int, f) -> void:
	for l in _listeners:
		(l as Callable).call(id, old, new_t, f)

# ------------------------------------------------------------------ the per-minute refresh
static func controlled_households() -> Array:
	var out: Array = []
	for pid in Players.ids():
		var h: int = Players.household_of(int(pid))
		if h > 0 and not out.has(h):
			out.append(h)
	if out.is_empty():
		out.append(Players.primary_household())
	return out

static func _resync() -> void:
	var w = WorldIface.world()
	if w == null or not ("folk" in w) or not (w.folk is Dictionary):
		return
	if (w.folk as Dictionary).size() == _world.size():
		return
	stats["resyncs"] = int(stats.get("resyncs", 0)) + 1
	for id in _world.keys():
		if not (w.folk as Dictionary).has(id):
			on_removed(int(id))
	for id2 in w.folk:
		if not _world.has(id2):
			on_added(w.folk[id2])

static func _classify_kind(f) -> int:
	return 1 if (f.has_meta("crowd") or f.has_meta("staff")) else 0

static func refresh(_total: int = 0) -> void:
	if stats.is_empty():
		reset()
	var t0 := Time.get_ticks_usec()
	_resync()
	var c: Dictionary = cfg()
	var now: int = SimEnv.now_min()
	var hh: Array = controlled_households()
	anchors = []
	controlled_ids = []
	var fixed_active := 0
	for id in _world:
		var f = _world[id]
		if _new.has(id) or not _kind.has(id):
			_kind[id] = _classify_kind(f)
		if int(_kind[id]) == 0:
			fixed_active += 1
			if hh.has(int(f.household_id)) and not f.has_meta("visitor") and not f.has_meta("away") and not f.has_meta("trip_zone"):
				anchors.append(InterestArea.make_anchor(f.tile))
				controlled_ids.append(int(id))
	if _has_focus:
		anchors.append(InterestArea.make_anchor(_focus))
	var sig: int = 0
	for a in anchors:
		sig = sig * 31 + int(a["tile"].x) * 1009 + int(a["tile"].y)
	_anchor_sig = sig
	var demote: int = int(c.get("demote_min", 10))
	var stick: int = int(c.get("stickiness", 4))
	var ranked: Array = []            # tiered ACTIVE people for the cap: [score, id]
	var active_n := fixed_active
	for id2 in _world:
		var f2 = _world[id2]
		var cur: int = int(_sets.tier_of.get(id2, -1))
		if int(_kind[id2]) == 0:
			if cur != ACTIVE:
				_assign(id2, ACTIVE, f2, cur)
			_new.erase(id2)
			continue
		var cd: Array = _cand.get(id2, [])
		if cd.size() < 5 or int(cd[2]) != f2.tile.x or int(cd[3]) != f2.tile.y or int(cd[4]) != sig:
			var cl: Array = InterestArea.classify(f2.tile, NeighborhoodLots.lot_at(f2.tile), anchors, c)
			cd = [int(cl[0]), int(cl[1]), f2.tile.x, f2.tile.y, sig]
			_cand[id2] = cd
			stats["classified"] = int(stats["classified"]) + 1
		else:
			stats["reused"] = int(stats["reused"]) + 1
		var want: int = int(cd[0])
		if _new.has(id2):
			_new.erase(id2)
			if _saved.has(id2):
				cur = int(_saved[id2])
				if cur != want and want > cur:      # a saved higher tier: keep it and let the hysteresis timer run
					_below[id2] = now
				_assign(id2, cur, f2, int(_sets.tier_of.get(id2, -1)))
			else:
				cur = want
				_assign(id2, want, f2, int(_sets.tier_of.get(id2, -1)))
		elif want < cur:
			_below.erase(id2)
			_assign(id2, want, f2, cur)
			cur = want
		elif want > cur:
			var since: int = int(_below.get(id2, now))
			_below[id2] = since
			if now - since >= demote:
				_below.erase(id2)
				_assign(id2, want, f2, cur)
				cur = want
		else:
			_below.erase(id2)
		if cur == ACTIVE:
			active_n += 1
			ranked.append([int(cd[1]) - (stick if int(_sets.tier_of.get(id2, -1)) == ACTIVE else 0), int(id2)])
	_saved.clear()
	var cap: int = int(c.get("active_cap", 60))
	if active_n > cap:
		ranked.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
		var keep: int = maxi(cap - fixed_active, 0)
		for i in range(keep, ranked.size()):
			var cid: int = int(ranked[i][1])
			_below.erase(cid)
			stats["capped"] = int(stats["capped"]) + 1
			_assign(cid, NEAR, _world[cid], ACTIVE)
	stats["refresh"] = int(stats["refresh"]) + 1
	stats["usec"] = int(stats["usec"]) + Time.get_ticks_usec() - t0

static func _assign(id: int, tier: int, f, old: int) -> void:
	var prev: int = _sets.put(id, tier, f)
	if prev == tier:
		return
	stats["changes"] = int(stats["changes"]) + 1
	if prev >= 0:
		if tier < prev:
			stats["promotions"] = int(stats["promotions"]) + 1
		else:
			stats["demotions"] = int(stats["demotions"]) + 1
	_notify(id, prev, tier, f)

# ------------------------------------------------------------------ save / load
static func to_dict() -> Dictionary:
	var tiers: Dictionary = {}
	for id in _sets.tier_of:
		if int(_kind.get(id, 0)) == 1:
			tiers[str(id)] = int(_sets.tier_of[id])
	var below: Dictionary = {}
	for id2 in _below:
		below[str(id2)] = int(_below[id2])
	return {"tiers": tiers, "below": below, "focus": [_focus.x, _focus.y] if _has_focus else []}

static func from_dict(d: Dictionary) -> void:
	_saved.clear()
	for k in d.get("tiers", {}):
		_saved[int(k)] = int(d["tiers"][k])
	_below.clear()
	for k2 in d.get("below", {}):
		_below[int(k2)] = int(d["below"][k2])
	var fc: Array = d.get("focus", [])
	_has_focus = fc.size() == 2
	if _has_focus:
		_focus = Vector2i(int(fc[0]), int(fc[1]))

## One line for logs / the benchmark.
static func describe() -> String:
	var ct: Array = counts()
	return "tiers active %d near %d town %d statistical %d (world %d); %s" % [ct[0], ct[1], ct[2], ct[3], _world.size(), str(stats)]
