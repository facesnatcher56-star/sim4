class_name PieEntries
extends RefCounted
## Keeps the interaction menu digestible: hides things this Folk can never do to this target, rewords "why not"
## reasons for players (no internal ids), and floats recently used actions to the top.
const NEVER_PATTERNS := ["already together", "divorce instead", "only for exes", "only after being cheated", "not for ", "needs trait", "already attached", "is away", "Too young", "Only adults", "Nothing to do here"]
const NOT_NEEDED := {"hunger": "Not hungry enough", "energy": "Not tired enough", "bladder": "Doesn't need the toilet", "hygiene": "Already clean",
	"social": "Doesn't need company", "fun": "Not bored", "comfort": "Already comfortable"}
const TOO_LOW := {"hunger": "Too hungry", "energy": "Too tired", "bladder": "Too desperate", "hygiene": "Too grimy", "social": "Too lonely", "fun": "Too bored", "comfort": "Too uncomfortable"}

## Last few actions the player chose (most recent first). Session only.
static var recent: Array = []

static func remember(def_id: String) -> void:
	recent.erase(def_id)
	recent.push_front(def_id)
	while recent.size() > 5:
		recent.pop_back()

static func is_never(reason: String) -> bool:
	for p in NEVER_PATTERNS:
		if p in reason:
			return true
	return false

static func label_of_trait(id: String) -> String:
	return str(UIU.tbl("traits").get(id, {}).get("label", UIU.sentence(id)))

static func label_of_mood(id: String) -> String:
	return Emotions.label(id) if Emotions.mood_defs().has(id) else UIU.sentence(id)

## Rewrites reasons built from raw ids ("needs trait glutton", "not in the mood (hunger too high)").
static func polish_reason(r: String) -> String:
	if r == "":
		return r
	var rx := RegEx.create_from_string("not in the mood \\((\\w+) too high\\)")
	var m := rx.search(r)
	if m != null:
		return r.replace(m.get_string(0), str(NOT_NEEDED.get(m.get_string(1), "Not in the mood")))
	rx = RegEx.create_from_string("(\\w+) too low")
	m = rx.search(r)
	if m != null and TOO_LOW.has(m.get_string(1)):
		return r.replace(m.get_string(0), str(TOO_LOW[m.get_string(1)]).to_lower())
	rx = RegEx.create_from_string("needs trait (\\w+)")
	m = rx.search(r)
	if m != null:
		return r.replace(m.get_string(0), "needs the %s trait" % label_of_trait(m.get_string(1)))
	rx = RegEx.create_from_string("not for (\\w+) folk")
	m = rx.search(r)
	if m != null:
		return r.replace(m.get_string(0), "not for %s Folk" % label_of_trait(m.get_string(1)))
	rx = RegEx.create_from_string("needs (\\w+) skill (\\d+)")
	m = rx.search(r)
	if m != null:
		return r.replace(m.get_string(0), "needs %s skill level %s" % [UIU.sentence(m.get_string(1)), m.get_string(2)])
	rx = RegEx.create_from_string("only while (\\w+)")
	m = rx.search(r)
	if m != null:
		return r.replace(m.get_string(0), "only while %s" % label_of_mood(m.get_string(1)).to_lower())
	rx = RegEx.create_from_string("needs (\\w+) above (\\d+)")
	m = rx.search(r)
	if m != null:
		return r.replace(m.get_string(0), "needs more %s (above %s)" % [m.get_string(1), m.get_string(2)])
	return r

## Sorts (recent + available first), drops never-available entries, polishes reasons. Entries keep the
## {id,label,category,enabled,reason} shape.
static func prepare(entries: Array) -> Array:
	var out: Array = []
	for e0 in entries:
		var e: Dictionary = (e0 as Dictionary).duplicate()
		if not bool(e["enabled"]):
			e["reason"] = polish_reason(str(e["reason"]))
			if is_never(str(e["reason"])):
				continue
		out.append(e)
	var rank := func(e: Dictionary) -> int:
		var i := recent.find(str(e["id"]))
		return i if i >= 0 else 99
	out.sort_custom(func(a, b):
		if a["enabled"] != b["enabled"]:
			return a["enabled"]
		var ra: int = rank.call(a)
		var rb: int = rank.call(b)
		if ra != rb:
			return ra < rb
		if a["category"] != b["category"]:
			return a["category"] < b["category"]
		return a["label"] < b["label"])
	return out

## Menu title for an object target.
static func object_title(object_id: int) -> String:
	var o = World.call("get_object", object_id) if World.has_method("get_object") else null
	if o == null:
		return "What should they do?"
	return str(UIU.tbl("objects").get(str(UIU.prop(o, "def_id", "")), {}).get("label", "Object"))

# ------------------------------------------------------------------ curated menus (data/menus.json)
static func menus() -> Dictionary:
	return SysUtil.table("menus")

static func max_flat() -> int:
	return int(menus().get("max_flat", 7))

static func _match(id: String, patterns: Array) -> bool:
	for p in patterns:
		var ps: String = str(p)
		if ps.ends_with("*"):
			if id.begins_with(ps.trim_suffix("*")):
				return true
		elif id == ps:
			return true
	return false

## What the player is shown for an object (or "self" / "ground"): only what can be done now, the object's hidden actions removed, the rest in named groups.
## Returns {main: [entries in order], groups: [{name, entries}], blocked: [{label, reason}] (up to 4: the things that cannot be done right now)}.
static func curate(entries: Array, object_def: String) -> Dictionary:
	var cfg: Dictionary = (menus().get("objects", {}) as Dictionary).get(object_def, {})
	var hide: Array = cfg.get("hide", [])
	var first: Array = cfg.get("first", [])
	var groups_cfg: Dictionary = cfg.get("groups", {})
	var main: Array = []
	var named: Dictionary = {}
	var blocked: Array = []
	for e0 in entries:
		var e: Dictionary = (e0 as Dictionary).duplicate()
		var id: String = str(e["id"])
		if _match(id, hide):
			continue
		if not bool(e["enabled"]):
			var why: String = polish_reason(str(e["reason"]))
			if not is_never(why) and blocked.size() < 4 and why != "Not possible right now" and why != "":
				blocked.append({"label": str(e["label"]), "reason": why})
			continue
		var g: String = str(e.get("group", ""))
		for gname in groups_cfg:
			if g != "":
				break
			if _match(id, groups_cfg[gname]):
				g = str(gname)
				break
		if g != "":
			if not named.has(g):
				named[g] = []
			(named[g] as Array).append(e)
		else:
			main.append(e)
	var rank := func(e: Dictionary) -> int:
		var fi := first.find(str(e["id"]))
		if fi >= 0:
			return fi
		var ri := recent.find(str(e["id"]))
		return 20 + ri if ri >= 0 else 99
	main.sort_custom(func(a, b):
		var ra: int = rank.call(a)
		var rb: int = rank.call(b)
		if ra != rb:
			return ra < rb
		if a["category"] != b["category"]:
			return a["category"] < b["category"]
		return a["label"] < b["label"])
	var groups: Array = []
	for gname in groups_cfg:
		if named.has(gname):
			groups.append({"name": str(gname), "entries": named[gname]})
	# too many left over: fold them into groups by category (the most used stay on top)
	if main.size() > max_flat():
		var keep: Array = main.slice(0, max_flat() - 2)
		var rest: Array = main.slice(max_flat() - 2)
		var by_cat: Dictionary = {}
		for e in rest:
			var c: String = str(e["category"])
			if not by_cat.has(c):
				by_cat[c] = []
			(by_cat[c] as Array).append(e)
		for c in by_cat:
			groups.append({"name": str(c), "entries": by_cat[c]})
		main = keep
	return {"main": main, "groups": groups, "blocked": blocked}
