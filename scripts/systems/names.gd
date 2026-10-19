class_name Names
extends RefCounted
## The name pool (data/names.json) and "no first name twice in the same town while it is in use" (living townies, household,
## visitors, staff and crowd all count).

static func firsts() -> Array:
	return SysUtil.table("names").get("first_names", ["Sam"])

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
static func pick_first(extra: Array = [], r: RandomNumberGenerator = null) -> String:
	var used: Dictionary = in_use()
	for e in extra:
		used[first_of(str(e))] = true
	var pool: Array = firsts().filter(func(n): return not used.has(str(n)))
	if pool.is_empty():
		return "Folk %d" % (used.size() + 1)
	var g: RandomNumberGenerator = r if r != null else SysUtil.rng
	return str(pool[g.randi_range(0, pool.size() - 1)])

static func pick_last(r: RandomNumberGenerator = null) -> String:
	var g: RandomNumberGenerator = r if r != null else SysUtil.rng
	var l: Array = lasts()
	return str(l[g.randi_range(0, l.size() - 1)])
