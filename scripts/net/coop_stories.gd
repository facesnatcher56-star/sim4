class_name CoopStories
extends RefCounted
## The town's stories for a waiting co-op player: the news log (`Story.news`) plus the public chronicle notes (`ChronicleHook.recent`), as
## short lines "Day N: text", newest last. The HOST builds them per peer through `CoopVisibility.visible_to(player, entry)` (entry = a Dictionary
## {kind, text, day, severity, subjects, lot}); a CLIENT never builds them, it shows the last `feed` the host sent inside a DELTA (key "s", only
## when the list changed). Notes the paper may not print (`public` false) never leave the host.

const MAX_LINES := 12
const MAX_TEXT := 160

## The lines a client last received (host: unused).
static var feed: Array = []

## Raw entries, oldest first (news log first, then chronicle notes not already in it).
static func entries() -> Array:
	var out: Array = []
	var seen := {}
	for n in Story.news:
		var text := str((n as Dictionary).get("text", ""))
		var key := "%d|%s" % [int((n as Dictionary).get("day", 0)), text]
		if text != "" and not seen.has(key):
			seen[key] = true
			out.append({"kind": "news", "text": text, "day": int((n as Dictionary).get("day", 0)), "severity": 1, "subjects": [], "lot": ""})
	for c in ChronicleHook.recent:
		if not bool((c as Dictionary).get("public", true)):
			continue
		var text2 := str((c as Dictionary).get("text", ""))
		var key2 := "%d|%s" % [int((c as Dictionary).get("day", 0)), text2]
		if text2 != "" and not seen.has(key2):
			seen[key2] = true
			out.append({"kind": str(c.get("kind", "chronicle")), "text": text2, "day": int(c.get("day", 0)), "severity": int(c.get("severity", 1)),
				"subjects": (c.get("subjects", []) as Array).duplicate(), "lot": str(c.get("lot", ""))})
	for i in out.size():
		out[i]["_i"] = i
	out.sort_custom(func(a, b): return int(a["day"]) < int(b["day"]) or (int(a["day"]) == int(b["day"]) and int(a["_i"]) < int(b["_i"])))      # by day, stable
	return out

## [[day, text], ...] for one player: visible entries only, the newest MAX_LINES, oldest first.
static func lines_for(player_id: int) -> Array:
	var out: Array = []
	for e in entries():
		if CoopVisibility.visible_to(player_id, e):
			out.append([int(e["day"]), str(e["text"]).left(MAX_TEXT)])
	return out.slice(maxi(out.size() - MAX_LINES, 0))

static func signature(lines: Array) -> String:
	return JSON.stringify(lines).sha256_text().substr(0, 12)

## Client: take what the host sent (bounded, plain values only).
static func apply(lines: Variant) -> void:
	feed = []
	if not (lines is Array):
		return
	for l in lines:
		if l is Array and (l as Array).size() == 2 and feed.size() < MAX_LINES:
			feed.append([int(l[0]), str(l[1]).left(MAX_TEXT)])

## What THIS machine shows: the host reads its own world, a client the last feed.
static func local_lines() -> Array:
	var ses := CoopSession.instance
	if ses != null and is_instance_valid(ses) and ses.role == "client":
		return feed
	return lines_for(Players.local_id)

static func text_of(line: Array) -> String:
	return "Day %d: %s" % [int(line[0]), str(line[1])]

static func reset() -> void:
	feed = []
