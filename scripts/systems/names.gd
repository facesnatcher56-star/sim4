class_name Names
extends RefCounted
## The name pool (data/names.json) and "no first name twice in the same town while it is in use" (living townies, household,
## visitors, staff and crowd all count).

static func firsts(sex: String = "") -> Array:
	if sex == "female" or sex == "male":
		var pool: Array = SysUtil.table("names").get(sex + "_names", [])
		if not pool.is_empty():
			return pool
	return SysUtil.table("names").get("first_names", ["Sam"])

static var _sets: Dictionary = {}
static var _sets_src = null

static func _set_of(sex: String) -> Dictionary:
	var src = SysUtil.table("names")
	if not is_same(src, _sets_src):
		_sets.clear()
		_sets_src = src
	if not _sets.has(sex):
		var d: Dictionary = {}
		for n in src.get(sex + "_names", []):
			d[str(n)] = true
		_sets[sex] = d
	return _sets[sex]

static func female_set() -> Dictionary:
	return _set_of("female")

static func male_set() -> Dictionary:
	return _set_of("male")

static func lasts() -> Array:
	return SysUtil.table("names").get("last_names", ["Doe"])

static func first_of(full: String) -> String:
	return full.get_slice(" ", 0)

## First names currently in use anywhere in town.
static func in_use() -> Dictionary:
	var used: Dictionary = {}
	for f in WorldIface.all_folk():
		used[first_of(str(f.name))] = true
	for t in Story.townies.values():
		if bool(t.get("alive", true)):
			used[first_of(str(t["name"]))] = true
	return used

## A first name nobody in town uses (and not in `extra`); falls back to a numbered one when the pool is exhausted.
static func pick_first(extra: Array = [], r: RandomNumberGenerator = null, sex: String = "") -> String:
	var used: Dictionary = in_use()
	for e in extra:
		used[first_of(str(e))] = true
	var pool: Array = firsts(sex).filter(func(n): return not used.has(str(n)))
	if pool.is_empty():
		return "Folk %d" % (used.size() + 1)
	var g: RandomNumberGenerator = r if r != null else SysUtil.rng
	return str(pool[g.randi_range(0, pool.size() - 1)])

static func pick_last(r: RandomNumberGenerator = null) -> String:
	var g: RandomNumberGenerator = r if r != null else SysUtil.rng
	var l: Array = lasts()
	return str(l[g.randi_range(0, l.size() - 1)])

## A few unused first names of `sex` to offer when the player names a baby.
static func suggestions(sex: String, n: int = 3, r: RandomNumberGenerator = null) -> Array:
	var used: Dictionary = in_use()
	var pool: Array = firsts(sex).filter(func(x): return not used.has(str(x)))
	var g: RandomNumberGenerator = r if r != null else SysUtil.rng
	var out: Array = []
	while out.size() < n and not pool.is_empty():
		var i: int = g.randi_range(0, pool.size() - 1)
		out.append(str(pool[i]))
		pool.remove_at(i)
	return out
