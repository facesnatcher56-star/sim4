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
