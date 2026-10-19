class_name UIU
extends RefCounted
## Shared UI helpers. Everything here is defensive (duck-typed) so the UI keeps working while
## other agents' code evolves behind the contract in ARCHITECTURE.md.

const MOOD_COLORS := {
	"happy": Color("#f2c94c"), "sad": Color("#5b8def"), "angry": Color("#e5534b"),
	"tense": Color("#c586e8"), "bored": Color("#8d99a6"), "energized": Color("#4cd694"),
	"uncomfortable": Color("#d9894a"), "focused": Color("#4cc9d9"), "flirty": Color("#f07fb0"),
	"neutral": Color("#9aa7b4"),
}

static func tbl(name: String) -> Dictionary:
	if Data.has_method("get_table"):
		var t = Data.call("get_table", name)
		if t is Dictionary:
			return t
	var d = Data.get(name)
	return d if d is Dictionary else {}

static var _cls_cache := {}
## Resolve a global class_name script at runtime (null if not present yet).
static func cls(name: String):
	if _cls_cache.has(name):
		return _cls_cache[name]
	for c in ProjectSettings.get_global_class_list():
		if c.get("class") == name:
			var sc = load(c.get("path"))
			_cls_cache[name] = sc
			return sc
	return null

static func connect_ev(sig: String, c: Callable) -> void:
	if Events.has_signal(sig) and not Events.is_connected(sig, c):
		Events.connect(sig, c)

static func get_folk(id: int):
	if World.has_method("get_folk"):
		return World.call("get_folk", id)
	return null

static func prop(o, key: String, default = null):
	if o == null:
		return default
	if o is Dictionary:
		return o.get(key, default)
	var v = o.get(key)
	return default if v == null else v

## Colour-blind-safe mood palette (Okabe-Ito based); used instead of MOOD_COLORS when the setting is on.
const MOOD_COLORS_CB := {
	"happy": Color("#f0e442"), "sad": Color("#0072b2"), "angry": Color("#d55e00"),
	"tense": Color("#cc79a7"), "bored": Color("#999999"), "energized": Color("#56b4e9"),
	"uncomfortable": Color("#e69f00"), "focused": Color("#009e73"), "flirty": Color("#ff9ec8"),
	"neutral": Color("#bbbbbb"),
}

static func mood_color(mood: String, fallback: Color = Color("#9aa7b4")) -> Color:
	var t: Dictionary = MOOD_COLORS_CB if GameSettings.colorblind() else MOOD_COLORS
	return t.get(mood, fallback)

static func level_color(ratio: float) -> Color:
	if GameSettings.colorblind():
		# Okabe-Ito: vermillion / orange / yellow / blue stay apart for every common colour-vision type
		if ratio < 0.2: return Color("#d55e00")
		if ratio < 0.4: return Color("#e69f00")
		if ratio < 0.65: return Color("#f0e442")
		return Color("#0072b2")
	# colour-blind friendly ramp (red -> orange -> yellow -> blue); bars also carry a number and a "!" when low
	if ratio < 0.2: return Color("#e5534b")
	if ratio < 0.4: return Color("#e8913d")
	if ratio < 0.65: return Color("#e6c84a")
	return Color("#3fa7d6")

static func stat_ratio(s) -> float:
	if s == null:
		return 0.0
	var lo := float(prop(s, "min", 0.0))
	var hi := float(prop(s, "max", 100.0))
	return clampf((float(prop(s, "value", 0.0)) - lo) / maxf(hi - lo, 0.001), 0.0, 1.0)

## Appearance isn't part of Folk (sim-core), so the UI keeps a folk-id -> Color registry (saved with the UI save slot).
static var folk_colors := {}

static func folk_color(folk) -> Color:
	var id := int(prop(folk, "id", -1))
	if folk_colors.has(id):
		return folk_colors[id]
	var ap = prop(folk, "appearance", null)
	if ap is Dictionary and ap.has("color"):
		return Color(str(ap["color"]))
	var h := hash(str(prop(folk, "name", "x")))
	return Color.from_hsv(float(absi(h) % 360) / 360.0, 0.5, 0.85)

static func buff_id(b) -> String:
	if b is Dictionary: return str(b.get("id", b.get("buff", "")))
	if b is String or b is StringName: return str(b)
	var v = b.get("id")
	if v == null: v = b.get("buff_id")
	return str(v) if v != null else str(b)

## Sentence case for an id or label ("hair_style" -> "Hair style"); String.capitalize() would give "Hair Style".
static func sentence(t: String) -> String:
	var s := t.replace("_", " ").strip_edges()
	return s.substr(0, 1).to_upper() + s.substr(1).to_lower() if s != "" else s

static func interaction_label(def_id: String) -> String:
	var t := tbl("interactions")
	if t.has(def_id):
		return str(t[def_id].get("label", sentence(def_id)))
	return sentence(def_id)

static func clock_text() -> String:
	if Clock.has_method("hour") and Clock.has_method("minute"):
		return "%02d:%02d" % [int(Clock.call("hour")), int(Clock.call("minute"))]
	return "--:--"

static func day_number() -> int:
	if Clock.has_method("day"):
		return int(Clock.call("day"))
	return 1

static func set_speed(s: int) -> void:
	if Clock.has_method("set_speed"): Clock.call("set_speed", s)
	else: Clock.set("speed", s)

static func get_speed() -> int:
	var s = Clock.get("speed")
	return int(s) if s != null else 1

## Push an interaction on a folk's queue with player priority (the command layer's "interact"). Returns false if it could not be created.
## extra: {tile, level} walks to a tile; other keys merge into the interaction params.
static func enqueue(folk, def_id: String, target_id: int, extra: Dictionary = {}) -> bool:
	if folk == null:
		return false
	return bool(Commands.run({"player_id": Players.LOCAL, "folk_id": int(folk.id), "action": "interact",
		"args": {"interaction_id": def_id, "target_id": target_id, "extra": extra}}).get("ok", false))

## Events.notification clashes with Node.notification(), so always go through emit_signal.
static func notify(text: String, kind: String = "info") -> void:
	Events.emit_signal("notification", text, kind)

static func make_label(text: String, size: int = 14, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
