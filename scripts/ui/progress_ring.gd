class_name ProgressRing
extends RefCounted
## Task 33.4 (view only, pure functions): the maths and the rules of the progress ring over a folk's head and of the bar on the queue chip.
## Source of truth is `Interaction.progress()` (elapsed / duration of a RUNNING action; a pure read). Data: data/progress_rings.json. Mode: Settings `progress_rings`
## (0 off, 1 selected folk only, 2 household (default), 3 everyone).

const PATH := "res://data/progress_rings.json"
const OFF := 0
const SELECTED := 1
const HOUSEHOLD := 2
const EVERYONE := 3

static var _cfg: Dictionary = {}
static var _loaded := false


static func cfg() -> Dictionary:
	if _loaded:
		return _cfg
	_loaded = true
	_cfg = {}
	if FileAccess.file_exists(PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			_cfg = parsed
	return _cfg


static func reload() -> void:
	_loaded = false


static func min_duration() -> float:
	return float(cfg().get("min_duration_min", 3.0))


## Fraction done (0..1) of an interaction that shows a ring, or -1 when it shows none: nothing running, still walking to it, or too short to be worth a ring.
static func fraction(inter: Variant) -> float:
	if inter == null:
		return -1.0
	if float(inter.duration()) < min_duration():
		return -1.0
	return float(inter.progress())


## Fraction for the queue chip: any running action with a length (even a short one), -1 otherwise.
static func chip_fraction(inter: Variant) -> float:
	return -1.0 if inter == null else float(inter.progress())


## Does the setting `mode` show a ring over this folk? `selected_id` / `selected_household` describe the selection (-1 = none).
static func shows_for(mode: int, folk_id: int, folk_household: int, selected_id: int, selected_household: int) -> bool:
	match mode:
		SELECTED:
			return folk_id == selected_id
		HOUSEHOLD:
			return folk_id == selected_id or (selected_household >= 0 and folk_household == selected_household and folk_household > 0)
		EVERYONE:
			return true
	return false


## The icon rule for an interaction: {shape, color}. First rule whose ids or tags match wins; the last rule is the fallback.
static func icon_for(def_id: String, tags: Array) -> Dictionary:
	for r in (cfg().get("icons", []) as Array):
		var rule: Dictionary = r
		if not rule.has("ids") and not rule.has("tags"):
			return rule
		if rule.has("ids") and def_id in (rule["ids"] as Array):
			return rule
		for t in (rule.get("tags", []) as Array):
			if str(t) in tags:
				return rule
	return {"shape": "dots", "color": "#e6edf5"}


## "40%" text for a fraction, "" when there is none.
static func percent_text(frac: float) -> String:
	return "" if frac < 0.0 else "%d%%" % int(round(frac * 100.0))


## Arc end angle (radians, from 12 o'clock clockwise) for the fill of a fraction.
static func arc_end(frac: float) -> float:
	return -PI * 0.5 + TAU * clampf(frac, 0.0, 1.0)
