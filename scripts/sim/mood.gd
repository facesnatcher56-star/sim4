class_name Mood
extends RefCounted
## Mood = argmax of summed buff mood weights. Intensity 1..3 at sums 1 / 3 / 6. Below 1 -> "neutral", 0.

const MOODS: Array[String] = ["happy", "sad", "angry", "tense", "bored", "energized", "uncomfortable", "focused", "flirty"]
const NEGATIVE: Array[String] = ["sad", "angry", "tense", "bored", "uncomfortable"]
const POSITIVE: Array[String] = ["happy", "energized", "focused", "flirty"]

## Sum of mood weights per mood for the folk's active buffs.
static func totals(folk) -> Dictionary:
	var t: Dictionary = {}
	for b in folk.buffs:
		var def: Dictionary = SimEnv.data().buff_def(str(b["id"]))
		var m: Dictionary = def.get("mood", {})
		for k in m:
			t[k] = float(t.get(k, 0.0)) + float(m[k])
	return t

static func compute(folk) -> Dictionary:
	var t := totals(folk)
	var best := ""
	var best_v := 0.0
	for m in MOODS:   # fixed order breaks ties deterministically
		var v: float = float(t.get(m, 0.0))
		if v > best_v:
			best_v = v
			best = m
	return {"mood": "neutral" if best == "" else best, "intensity": intensity_for(best_v)}

static func intensity_for(total: float) -> int:
	if total >= 6.0:
		return 3
	if total >= 3.0:
		return 2
	if total >= 1.0:
		return 1
	return 0

## Negative = unpleasant buff, positive = pleasant, based on its mood weights.
static func buff_valence(buff_id: String) -> float:
	var def: Dictionary = SimEnv.data().buff_def(buff_id)
	var m: Dictionary = def.get("mood", {})
	var v := 0.0
	for k in m:
		if NEGATIVE.has(str(k)):
			v -= float(m[k])
		elif POSITIVE.has(str(k)):
			v += float(m[k])
	return v
