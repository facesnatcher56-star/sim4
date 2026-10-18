class_name ShareValidateTown
extends RefCounted
## Validation of a shared town file (.sim4town): an envelope {format, version, title, from, day, save, chronicle, inbox}.
## The embedded save is checked at the top level and for the people (folk and townies), bounded everywhere (size, depth, finite
## numbers, short strings, no paths), version-checked (never newer or older than SaveLoad.VERSION) and its own `share` block is
## dropped: gifts come only from the envelope's `inbox`.

static func town(raw: Variant) -> Dictionary:
	var e := ShareValidate.check_head(raw, "sim4town", "town_file_keys")
	if e != "":
		return ShareValidate.fail(e)
	var d: Dictionary = raw
	if not (d.get("save", null) is Dictionary):
		return ShareValidate.fail("the town has no save")
	var scan := ShareClean.scan(d, {}, 0, 200000)
	if scan != "":
		return ShareValidate.fail(scan)
	var sr := save_part(d["save"])
	if not bool(sr["ok"]):
		return sr
	var gr := ShareValidate.gifts(d.get("inbox", []))
	if not bool(gr["ok"]):
		return gr
	var cr := ShareValidate.lines(d.get("chronicle", []), int(ShareClean.cap("max_chronicle", 200)))
	if not bool(cr["ok"]):
		return cr
	var title := ShareClean.text(d.get("title", ""), int(ShareClean.cap("max_title", 48)))
	var out: Dictionary = {"format": "sim4town", "version": 1, "title": title if title != "" else "A shared town",
		"from": ShareClean.text(d.get("from", ""), int(ShareClean.cap("max_name", 32))),
		"day": ShareClean.clampi_(d.get("day", 0), 0, 1000000), "save": sr["data"], "chronicle": cr["data"], "inbox": gr["data"]}
	return ShareValidate.good(out)

static func save_part(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return ShareValidate.fail("the town save is malformed")
	var d: Dictionary = (raw as Dictionary).duplicate(true)
	if str(d.get("format", "")) != SaveLoad.FORMAT:
		return ShareValidate.fail("this is not a Sim 4 save")
	if not ShareClean.is_whole(d.get("version", null)):
		return ShareValidate.fail("the save has no version")
	if int(d["version"]) < SaveLoad.VERSION:
		return ShareValidate.fail(SaveLoad.OLD_SAVE_MSG)
	if int(d["version"]) > SaveLoad.VERSION:
		return ShareValidate.fail("this town is from a newer version of the game")
	var u := ShareValidate.unknown_key(d, ShareClean.cap("town_top_keys", []))
	if u != "":
		return ShareValidate.fail("unexpected save field '%s'" % u)
	for k in ["world", "systems"]:
		if not (d.get(k, null) is Dictionary):
			return ShareValidate.fail("the save is missing '%s'" % k)
	if not (d.get("folk", null) is Array):
		return ShareValidate.fail("the save is missing its folk")
	var su := ShareValidate.unknown_key(d["systems"], ShareClean.cap("town_system_keys", []))
	if su != "":
		return ShareValidate.fail("unexpected system '%s'" % su)
	for k2 in ["day", "clock_total", "next_folk_id"]:
		if d.has(k2) and (not ShareClean.is_whole(d[k2]) or int(d[k2]) < 0):
			return ShareValidate.fail("the save has a bad '%s'" % k2)
	d["label"] = ShareClean.text(d.get("label", ""), int(ShareClean.cap("max_title", 48)))
	d["household_name"] = ShareClean.text(d.get("household_name", ""), int(ShareClean.cap("max_title", 48)))
	for f in d["folk"]:
		var fe := _person(f, true)
		if fe != "":
			return ShareValidate.fail(fe)
	var story: Variant = (d["systems"] as Dictionary).get("story", {})
	if not (story is Dictionary):
		return ShareValidate.fail("the town story is malformed")
	var tn: Variant = (story as Dictionary).get("townies", {})
	if not (tn is Dictionary):
		return ShareValidate.fail("the townies are malformed")
	for tid in tn:
		if not str(tid).is_valid_int():
			return ShareValidate.fail("a townie has a bad id")
		var te := _person(tn[tid], false)
		if te != "":
			return ShareValidate.fail(te)
	(d["systems"] as Dictionary).erase("share")
	return ShareValidate.good(d)

## Types of the fields the loaders read without checking; names are sanitised in place. Returns "" when fine.
static func _person(p: Variant, is_folk: bool) -> String:
	if not (p is Dictionary):
		return "a person is malformed"
	var d: Dictionary = p
	if not ShareClean.is_whole(d.get("id", null)) or int(d["id"]) < 0:
		return "a person has a bad id"
	if not (d.get("name", null) is String):
		return "a person has no name"
	d["name"] = ShareClean.text(d["name"], int(ShareClean.cap("max_name", 32)))
	if d["name"] == "":
		d["name"] = "Someone"
	if not (d.get("traits", []) is Array):
		return "a person has bad traits"
	for t in d.get("traits", []):
		if not (t is String):
			return "a person has bad traits"
	for k in (["needs", "skills"] if is_folk else ["appearance"]):
		if d.has(k) and not (d[k] is Dictionary):
			return "a person has a bad '%s'" % k
	if is_folk:
		if not (d.get("tile", null) is Array) or (d["tile"] as Array).size() != 2 or not ShareClean.is_num(d["tile"][0]) or not ShareClean.is_num(d["tile"][1]):
			return "a person has a bad position"
		for lk in ["memory", "buffs"]:
			if d.has(lk) and not (d[lk] is Array):
				return "a person has a bad '%s'" % lk
		if d.has("relationships") and not (d["relationships"] is Dictionary):
			return "a person has bad relationships"
		return ""
	if not ShareClean.is_num(d.get("age_days", null)) or not ShareClean.is_whole(d.get("level", null)) or not ShareClean.is_whole(d.get("coins", null)):
		return "a townie has bad numbers"
	if not (d.get("career", null) is String) or not (d.get("alive", null) is bool):
		return "a townie has bad fields"
	return ""
