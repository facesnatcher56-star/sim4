class_name ShareCards
extends RefCounted
## Family-history / legacy cards: a small, shareable summary of a household (text lines plus a few numbers). Built from
## validated household data, exported as .sim4card (JSON) or as a PNG by the card dialog, and validated when opened.

static func from_household(h: Dictionary) -> Dictionary:
	var members: Array = h.get("members", [])
	var names: Array = []
	var traits: Dictionary = {}
	var best_skill := ""
	var best_level := -1
	for m in members:
		names.append("%s (%s)" % [m["name"], str(m["stage"]).replace("_", " ")])
		for t in m["traits"]:
			traits[t] = int(traits.get(t, 0)) + 1
		for s in m["skills"]:
			if int(m["skills"][s]["level"]) > best_level:
				best_level = int(m["skills"][s]["level"])
				best_skill = "%s: %s level %d" % [m["name"], s, best_level]
	var leg: Dictionary = h.get("legacy", {})
	var lines: Array = []
	lines.append("%d people, %d generation%s." % [members.size(), int(leg.get("generations", 1)), "" if int(leg.get("generations", 1)) == 1 else "s"])
	if not traits.is_empty():
		var tn: Array = traits.keys()
		tn.sort_custom(func(a, b): return int(traits[a]) > int(traits[b]) or (int(traits[a]) == int(traits[b]) and str(a) < str(b)))
		var labels: Array = []
		for t2 in tn.slice(0, 4):
			labels.append(str(SimEnv.data().trait_def(t2).get("label", t2)))
		lines.append("Known for being " + ", ".join(labels).to_lower() + ".")
	if best_skill != "" and best_level > 0:
		lines.append("Best skill: " + best_skill + ".")
	for l in (h.get("history", []) as Array).slice(-6):
		lines.append(str(l))
	var stats: Dictionary = {"members": members.size(), "generations": int(leg.get("generations", 1)), "children": int(leg.get("children", 0)),
		"oldest_days": float(leg.get("oldest_days", 0.0)), "day": int(h.get("day", 0))}
	return {"format": "sim4card", "version": 1, "title": str(h.get("title", "A family")), "lines": lines, "stats": stats, "members": names}

## Card for ids on this lot or in town (goes through the same export + validation as a household file).
static func for_ids(ids: Array, title: String = "") -> Dictionary:
	var v := ShareValidate.household(ShareExport.household(ids, title))
	if not bool(v["ok"]):
		return {}
	return from_household(v["data"])

static func text(card: Dictionary) -> String:
	var out: Array = [str(card.get("title", "")), ""]
	out.append_array(card.get("members", []))
	out.append("")
	out.append_array(card.get("lines", []))
	return "\n".join(out)

static func export_json(card: Dictionary) -> Dictionary:
	return ShareFile.write("card", str(card.get("title", "card")), card)

static func validate(raw: Variant) -> Dictionary:
	var e := ShareValidate.check_head(raw, "sim4card", "card_keys")
	if e != "":
		return ShareValidate.fail(e)
	var scan := ShareClean.scan(raw)
	if scan != "":
		return ShareValidate.fail(scan)
	var d: Dictionary = raw
	var ln := ShareValidate.lines(d.get("lines", []), 20)
	var mn := ShareValidate.lines(d.get("members", []), int(ShareClean.cap("max_members", 8)))
	if not bool(ln["ok"]):
		return ln
	if not bool(mn["ok"]):
		return mn
	var st: Variant = d.get("stats", {})
	if not (st is Dictionary) or ShareValidate.unknown_key(st, ["members", "generations", "children", "oldest_days", "day"]) != "":
		return ShareValidate.fail("the card statistics are malformed")
	var stats: Dictionary = {"members": ShareClean.clampi_(st.get("members", 0), 0, 99), "generations": ShareClean.clampi_(st.get("generations", 1), 1, 20, 1),
		"children": ShareClean.clampi_(st.get("children", 0), 0, 99), "oldest_days": ShareClean.clampf_(st.get("oldest_days", 0), 0, 400), "day": ShareClean.clampi_(st.get("day", 0), 0, 1000000)}
	return ShareValidate.good({"format": "sim4card", "version": 1, "title": ShareClean.text(d.get("title", ""), int(ShareClean.cap("max_title", 48))),
		"lines": ln["data"], "stats": stats, "members": mn["data"]})
