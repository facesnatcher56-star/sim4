class_name TownNews
extends RefCounted
## The town's news (task 14, communication and media): every PUBLIC chronicle line (births, weddings, deaths, incidents, the places' own news, school and
## league results ...) is kept for a while so the newspaper stand, the radio and the TV news can read it out. The chronicle hook itself keeps only 40
## unsaved entries; this store keeps the last `CAP` and is saved in the `life` block.
##   TownNews.latest(n, min_severity)   newest first
##   TownNews.bulletin(day)             the top lines of today and yesterday (severity first, then newest): what the news reads
## Tier: event driven (one append per chronicle line), nothing per minute. Cap 150.

const CAP := 150

static var items: Array = []             # [{day, kind, text, severity}] oldest first

static func reset() -> void:
	items.clear()

static func on_chronicle(p: Dictionary) -> void:
	if not bool(p.get("public", true)):
		return
	items.append({"day": int(p.get("day", SysUtil.day())), "kind": str(p.get("kind", "")), "text": str(p.get("text", "")), "severity": int(p.get("severity", 1))})
	while items.size() > CAP:
		items.pop_front()

static func latest(n: int = 8, min_severity: int = 0) -> Array:
	var out: Array = []
	for i in range(items.size() - 1, -1, -1):
		if int(items[i]["severity"]) >= min_severity:
			out.append(items[i])
			if out.size() >= n:
				break
	return out

static func bulletin(day: int = -1, n: int = 3) -> Array:
	if day < 0:
		day = SysUtil.day()
	var rows: Array = []
	for i in items.size():
		if int(items[i]["day"]) >= day - 1:
			rows.append([int(items[i]["severity"]), i])
	rows.sort_custom(func(a, b): return int(a[0]) > int(b[0]) or (int(a[0]) == int(b[0]) and int(a[1]) > int(b[1])))
	var out: Array = []
	for r in rows.slice(0, n):
		out.append(items[int(r[1])])
	return out

static func to_dict() -> Dictionary:
	return {"items": items.duplicate(true)}

static func from_dict(d: Dictionary) -> void:
	reset()
	items = (d.get("items", []) as Array).duplicate(true)
	for it in items:
		it["day"] = int(it["day"])
		it["severity"] = int(it["severity"])
