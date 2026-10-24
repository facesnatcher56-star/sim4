class_name Mood
extends RefCounted
## Mood = argmax of summed buff mood weights. Intensity 1..3 at sums 1 / 3 / 6. Below 1 -> "neutral", 0.

## The first nine are the original set; the rest are the richer emotions (see data/emotions.json for their effects).
## Order matters: ties are broken by position, so originals win ties.
const MOODS: Array[String] = ["happy", "sad", "angry", "tense", "bored", "energized", "uncomfortable", "focused", "flirty",
	"confident", "embarrassed", "inspired", "playful", "dazed", "jealous", "lonely", "nostalgic", "anxious", "content", "guilty", "proud"]
const NEGATIVE: Array[String] = ["sad", "angry", "tense", "bored", "uncomfortable", "embarrassed", "dazed", "jealous", "lonely", "anxious", "guilty"]
const POSITIVE: Array[String] = ["happy", "energized", "focused", "flirty", "confident", "inspired", "playful", "content", "proud"]

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
	var lift: float = need_lift(folk)
	var best := ""
	var best_v := 0.0
	for m in MOODS:   # fixed order breaks ties deterministically
		var v: float = float(t.get(m, 0.0)) * (lift if POSITIVE.has(m) else 1.0)
		if v > best_v:
			best_v = v
			best = m
	return {"mood": "neutral" if best == "" else best, "intensity": intensity_for(best_v)}

## Task 63: mood follows the needs. Every need far below zero (under -50) takes a third off the pleasant moods, so a good day out does not
## read "Happy" at -100 fun; the unpleasant moods are unchanged.
static func need_lift(folk) -> float:
	var low: int = 0
	if not ("needs" in folk):
		return 1.0
	for nid in folk.needs:
		if (folk.needs[nid] as Stat).value < -50.0:
			low += 1
	return maxf(1.0 - 0.34 * float(low), 0.2)

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

## Mood detail for the UI: which buffs push which mood, strongest first.
## Returns {mood, intensity, total, rows:[{id, label, weights:{mood:w}, toward:float, hidden:bool}], runner_up, runner_total}.
static func breakdown(folk) -> Dictionary:
	var m := compute(folk)
	var t := totals(folk)
	var best: String = str(m["mood"])
	var rows: Array = []
	for b in folk.buffs:
		var bid: String = str(b["id"])
		var def: Dictionary = SimEnv.data().buff_def(bid)
		var w: Dictionary = def.get("mood", {})
		if w.is_empty():
			continue
		var toward: float = float(w.get(best, 0.0)) if best != "neutral" else 0.0
		rows.append({"id": bid, "label": str(def.get("label", bid)), "weights": w.duplicate(), "toward": toward, "hidden": bool(def.get("hidden", false))})
	rows.sort_custom(func(a, b): return float(a["toward"]) > float(b["toward"]))
	var runner := ""
	var runner_v := 0.0
	for k in MOODS:
		if k != best and float(t.get(k, 0.0)) > runner_v:
			runner_v = float(t.get(k, 0.0))
			runner = k
	return {"mood": best, "intensity": int(m["intensity"]), "total": float(t.get(best, 0.0)), "rows": rows, "runner_up": runner, "runner_total": runner_v}
