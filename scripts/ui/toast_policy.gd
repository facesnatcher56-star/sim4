class_name ToastPolicy
extends RefCounted
## Decides what the toast feed shows: drops repeats, rewrites awkward system wording, and collapses
## whim notifications into one digest line (otherwise ~12 per day).
const DEDUPE_SEC := 12.0
const WHIM_DIGEST_SEC := 25.0

var _recent: Dictionary = {}          # text -> last shown (seconds)
var whim_names: Array = []
var whim_count := 0
var whim_points := 0
var whim_started := -1.0
var _re_pts := RegEx.create_from_string("\\(\\+(\\d+)\\)")

## Returns {"action": "show"|"drop"|"whim"|"offer", "text": String, "kind": String}.
func filter(text: String, kind: String, now: float) -> Dictionary:
	if kind == "job_offer":
		return {"action": "offer", "text": text, "kind": kind}
	if kind == "goal" and " fulfilled a whim" in text:
		_add_whim(text, now)
		return {"action": "whim", "text": "", "kind": kind}
	text = polish(text)
	if (kind == "travel" and " head" in text and not "hospital" in text) or (kind == "relationship" and " met " in text):
		return {"action": "drop", "text": text, "kind": kind}          # playtest: routine lines (you just sent them; you met someone) filled the screen
	if _recent.has(text) and now - float(_recent[text]) < DEDUPE_SEC:
		return {"action": "drop", "text": text, "kind": kind}
	_recent[text] = now
	if _recent.size() > 60:
		for k in _recent.keys():
			if now - float(_recent[k]) > DEDUPE_SEC:
				_recent.erase(k)
	return {"action": "show", "text": text, "kind": kind}

func _add_whim(text: String, now: float) -> void:
	var who := text.get_slice(" fulfilled a whim", 0)
	if not whim_names.has(who):
		whim_names.append(who)
	whim_count += 1
	var m := _re_pts.search(text)
	if m != null:
		whim_points += int(m.get_string(1))
	if whim_started < 0.0:
		whim_started = now

func whim_due(now: float) -> bool:
	return whim_count > 0 and now - whim_started >= WHIM_DIGEST_SEC

## Digest text, and resets the counters.
func take_whim_digest() -> String:
	var who: String = ", ".join(whim_names) if whim_names.size() <= 2 else "%s and %d others" % [whim_names[0], whim_names.size() - 1]
	var t := "%s fulfilled %s (+%d satisfaction)" % [who, "a whim" if whim_count == 1 else "%d whims" % whim_count, whim_points]
	whim_names.clear()
	whim_count = 0
	whim_points = 0
	whim_started = -1.0
	return t

## Small wording fixes for system strings.
static func polish(t: String) -> String:
	t = t.replace("widow(er)", "widowed")
	t = t.replace("is a widowed now", "is widowed now")
	t = t.replace("fiance(e)", "fiance")
	var marker := "is ready for a promotion but needs: "
	if marker in t:
		var head := t.get_slice(marker, 0)
		var reqs: Array = []
		for r in t.get_slice(marker, 1).split(", "):
			reqs.append(CareerDialog.nice_requirement(r.strip_edges()))
		t = head + marker + ", ".join(reqs)
	return t.strip_edges()

## Toast duration grows with text length.
static func duration_for(text: String) -> float:
	return clampf(3.5 + float(text.length()) / 22.0, 4.0, 9.0)
