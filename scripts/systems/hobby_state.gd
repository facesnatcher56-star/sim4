class_name HobbyState
extends RefCounted
## Hobby bookkeeping (task 14): the community garden plots (how often they were tended), photographs taken, collections of rocks, bugs and stamps (eight
## specimens to a set, each seen how many times), the biggest fish, and sets already donated to the museum. Saved in the `life` block (`hobby`).
## Rolls use their own seeded stream (LifeFame.rng is for scores; this one is for finds and catches).

const SEED := 140101

static var plots: Dictionary = {}         # person id -> {tends, day}
static var photos: Dictionary = {}        # person id -> unsold photographs
static var collections: Dictionary = {}   # person id -> {kind: {specimen id: count}}
static var donated: Dictionary = {}       # person id -> {kind: times}
static var rng: RandomNumberGenerator = RandomNumberGenerator.new()

static func reset() -> void:
	plots.clear()
	photos.clear()
	collections.clear()
	donated.clear()
	rng = RandomNumberGenerator.new()
	rng.seed = SEED

static func cfg() -> Dictionary:
	return LifeDefs.cfg("hobbies")

static func coll_defs() -> Dictionary:
	return LifeDefs.cfg("collections")

static func items(kind: String) -> Array:
	return (coll_defs().get(kind, {}) as Dictionary).get("items", [])

static func owned(id: int, kind: String) -> Dictionary:
	return ((collections.get(id, {}) as Dictionary).get(kind, {}) as Dictionary)

static func found_count(id: int, kind: String) -> int:
	return owned(id, kind).size()

static func complete(id: int, kind: String) -> bool:
	return not items(kind).is_empty() and found_count(id, kind) >= items(kind).size()

## Draw a specimen by rarity weight; returns {id, label, new: bool, count}.
static func find(id: int, kind: String, luck: float = 0.0) -> Dictionary:
	var its: Array = items(kind)
	if its.is_empty():
		return {}
	var total := 0.0
	for it in its:
		total += float(it["weight"])
	var roll: float = rng.randf() * total
	var pick: Dictionary = its[its.size() - 1]
	for it2 in its:
		roll -= float(it2["weight"]) * (1.0 + (luck if float(it2["weight"]) < 10.0 else 0.0))
		if roll <= 0.0:
			pick = it2
			break
	if not collections.has(id):
		collections[id] = {}
	if not (collections[id] as Dictionary).has(kind):
		collections[id][kind] = {}
	var c: Dictionary = collections[id][kind]
	var is_new: bool = not c.has(str(pick["id"]))
	c[str(pick["id"])] = int(c.get(str(pick["id"]), 0)) + 1
	return {"id": str(pick["id"]), "label": str(pick["label"]), "new": is_new, "count": int(c[str(pick["id"])])}

static func to_dict() -> Dictionary:
	return {"plots": SysUtil.str_keys(plots).duplicate(true), "photos": SysUtil.str_keys(photos), "collections": SysUtil.str_keys(collections).duplicate(true),
		"donated": SysUtil.str_keys(donated).duplicate(true), "rng_state": str(rng.state)}

static func from_dict(d: Dictionary) -> void:
	reset()
	for k in (d.get("plots", {}) as Dictionary):
		plots[int(str(k))] = {"tends": int(d["plots"][k]["tends"]), "day": int(d["plots"][k]["day"])}
	for k2 in (d.get("photos", {}) as Dictionary):
		photos[int(str(k2))] = int(d["photos"][k2])
	for k3 in (d.get("collections", {}) as Dictionary):
		var per: Dictionary = {}
		for kind in d["collections"][k3]:
			var c: Dictionary = {}
			for sid in d["collections"][k3][kind]:
				c[str(sid)] = int(d["collections"][k3][kind][sid])
			per[str(kind)] = c
		collections[int(str(k3))] = per
	for k4 in (d.get("donated", {}) as Dictionary):
		var dn: Dictionary = {}
		for kind2 in d["donated"][k4]:
			dn[str(kind2)] = int(d["donated"][k4][kind2])
		donated[int(str(k4))] = dn
	if d.has("rng_state"):
		rng.state = int(str(d["rng_state"]))
