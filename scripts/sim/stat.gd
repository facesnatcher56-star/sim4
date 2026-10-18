class_name Stat
extends RefCounted
## Generic bounded value with decay and thresholds. Used for needs (and usable for relationship tracks, object state).

var id: String = ""
var value: float = 0.0
@warning_ignore("shadowed_global_identifier")
var min: float = -100.0
@warning_ignore("shadowed_global_identifier")
var max: float = 100.0
var decay_per_min: float = 0.0
## Array of {"below": x, "buff": id} and/or {"above": x, "buff": id}
var thresholds: Array = []

static func from_def(p_id: String, def: Dictionary) -> Stat:
	var s := Stat.new()
	s.id = p_id
	s.min = float(def.get("min", -100.0))
	s.max = float(def.get("max", 100.0))
	s.value = clampf(float(def.get("start", s.max * 0.5)), s.min, s.max)
	s.decay_per_min = float(def.get("decay_per_min", 0.0))
	s.thresholds = def.get("thresholds", []).duplicate(true)
	return s

## Apply decay for `minutes` game minutes. `mult` is the product of all decay modifiers.
func tick(minutes: float, mult: float = 1.0) -> void:
	if decay_per_min != 0.0:
		value = clampf(value - decay_per_min * mult * minutes, min, max)

func add(delta: float) -> float:
	value = clampf(value + delta, min, max)
	return value

func set_value(v: float) -> void:
	value = clampf(v, min, max)

## 0..1 fill ratio.
func ratio() -> float:
	if max <= min:
		return 0.0
	return (value - min) / (max - min)

## All buff ids this stat can ever fire (used to remove the stale ones).
func all_threshold_buffs() -> Array:
	var out: Array = []
	for t in thresholds:
		var b: String = str(t.get("buff", ""))
		if b != "" and not out.has(b):
			out.append(b)
	return out

## Buff ids that should currently be active: only the most severe "below" band and the most severe "above" band.
func active_threshold_buffs() -> Array:
	var best_below: Variant = null
	var best_above: Variant = null
	for t in thresholds:
		if t.has("below") and value < float(t["below"]):
			if best_below == null or float(t["below"]) < float(best_below["below"]):
				best_below = t
		if t.has("above") and value > float(t["above"]):
			if best_above == null or float(t["above"]) > float(best_above["above"]):
				best_above = t
	var out: Array = []
	if best_below != null:
		out.append(str(best_below["buff"]))
	if best_above != null:
		out.append(str(best_above["buff"]))
	return out
