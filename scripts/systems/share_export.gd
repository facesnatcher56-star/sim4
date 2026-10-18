class_name ShareExport
extends RefCounted
## Building shareable data from the running game: households (player households and townie families), whole towns, and
## gifts left in an exported town file. The output is plain data; ShareFile writes it and ShareValidate checks it on the way back.

# ------------------------------------------------------------------ which households can be exported
## [{key, label, ids, townies}] : every player household on the lot, then each family of townies.
static func households() -> Array:
	var out: Array = []
	var by_h: Dictionary = {}
	for f in SysUtil.residents():
		var arr: Array = by_h.get(int(f.household_id), [])
		arr.append(int(f.id))
		by_h[int(f.household_id)] = arr
	var hids: Array = by_h.keys()
	hids.sort()
	for h in hids:
		var ids: Array = by_h[h]
		ids.sort()
		out.append({"key": "h%d" % h, "label": "%s (your household)" % ShareValidate.surname(Family.name_of(int(ids[0]))), "ids": ids, "townies": false})
	var seen: Dictionary = {}
	var tids: Array = []
	for t in Story.alive_townies():
		tids.append(int(t["id"]))
	tids.sort()
	for tid in tids:
		if seen.has(tid):
			continue
		var comp: Array = _component(tid, tids)
		for c in comp:
			seen[c] = true
		comp.sort()
		out.append({"key": "t%d" % tid, "label": "%s (townies)" % ShareValidate.surname(Story.name_of(tid)), "ids": comp, "townies": true})
	return out

static func _component(start: int, pool: Array) -> Array:
	var comp: Array = [start]
	var i := 0
	while i < comp.size() and comp.size() < int(ShareClean.cap("max_members", 8)):
		var cur: int = comp[i]
		i += 1
		var near: Array = []
		for p in (Family.parents.get(cur, []) as Array):
			near.append(int(p))
		for ch in Family.parents:
			if (Family.parents[ch] as Array).has(cur):
				near.append(int(ch))
		if Family.spouses.has(cur):
			near.append(int(Family.spouses[cur]))
		for n in near:
			if pool.has(n) and not comp.has(n) and comp.size() < int(ShareClean.cap("max_members", 8)):
				comp.append(n)
	return comp

# ------------------------------------------------------------------ household
## Raw (not yet validated) household data for the given person ids (Folk on the lot or Story townies).
static func household(ids: Array, title: String = "") -> Dictionary:
	var members: Array = []
	var ref_of: Dictionary = {}
	for id in ids:
		if members.size() >= int(ShareClean.cap("max_members", 8)):
			break
		var m := member(int(id))
		if m.is_empty():
			continue
		m["ref"] = members.size() + 1
		ref_of[int(id)] = m["ref"]
		members.append(m)
	var out: Dictionary = {"format": "sim4household", "version": 1, "title": title, "day": SysUtil.day(), "members": members}
	if out["title"] == "" and not members.is_empty():
		out["title"] = "The %s family" % ShareValidate.surname(str(members[0]["name"]))
	out["relations"] = _relations(ref_of)
	out["parents"] = _parents(ref_of)
	out["history"] = history_for(members)
	var oldest := 0.0
	for m2 in members:
		oldest = maxf(oldest, float(m2["age_days"]))
	var kids := 0
	for p in out["parents"]:
		kids += 1
	out["legacy"] = {"members": members.size(), "oldest_days": oldest, "generations": _generations(out["parents"]), "children": kids}
	return out

static func member(id: int) -> Dictionary:
	var f = SysUtil.folk(id)
	var info := Family.person_info(id)
	if info.get("name", "Someone") == "Someone" and f == null and not Story.townies.has(id):
		return {}
	var m: Dictionary = {"name": str(info["name"]), "stage": str(info["stage"]), "age_days": float(info["age_days"]),
		"traits": (info["traits"] as Array).duplicate(), "appearance": (info["appearance"] as Dictionary).duplicate(true),
		"skills": {}, "aspiration": "", "memories": [], "career": "", "level": 1}
	var born: int = int((Family.people.get(id, {}) as Dictionary).get("born_day", 0))
	m["birth_doy"] = posmod(born, maxi(int(Aging.days_per_year()), 1))
	if f != null:
		for s in f.skills:
			m["skills"][s] = {"level": int(f.skills[s].get("level", 0)), "xp": float(f.skills[s].get("xp", 0.0))}
		m["aspiration"] = str((Goals.profiles.get(id, {}) as Dictionary).get("aspiration", ""))
		var mem: Array = f.memory.duplicate()
		mem.sort_custom(func(a, b): return absf(float(a.get("value", 0))) > absf(float(b.get("value", 0))))
		for e in mem.slice(0, int(ShareClean.cap("max_memories", 5))):
			m["memories"].append({"key": str(e.get("key", "")), "value": clampf(float(e.get("value", 0.0)), -1.0, 1.0)})
		var job: Dictionary = Careers.jobs.get(id, {})
		m["career"] = str(job.get("career", ""))
		m["level"] = int(job.get("level", 1))
	else:
		var t: Dictionary = Story.townies.get(id, {})
		m["career"] = str(t.get("career", ""))
		m["level"] = int(t.get("level", 1))
		var sh: Dictionary = t.get("shared", {})
		m["skills"] = (sh.get("skills", {}) as Dictionary).duplicate(true)
		m["aspiration"] = str(sh.get("aspiration", ""))
		m["memories"] = (sh.get("memories", []) as Array).duplicate(true)
		if sh.has("birth_doy"):
			m["birth_doy"] = int(sh["birth_doy"])
	return m

static func _relations(ref_of: Dictionary) -> Array:
	var out: Array = []
	var ids: Array = ref_of.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a: int = ids[i]
			var b: int = ids[j]
			if not RelationshipService.knows(a, b):
				continue
			var fl: Dictionary = (RelationshipService.pairs[SysUtil.pair_key(a, b)] as Dictionary).get("flags", {})
			var kind := "friend"
			for k in ["spouse", "partner", "family"]:
				if fl.get(k, false):
					kind = k
					break
			out.append({"a": ref_of[a], "b": ref_of[b], "kind": kind, "friendship": RelationshipService.value(a, b, "friendship"),
				"romance": RelationshipService.value(a, b, "romance")})
	return out

static func _parents(ref_of: Dictionary) -> Array:
	var out: Array = []
	for child in ref_of:
		for p in (Family.parents.get(child, []) as Array):
			if ref_of.has(int(p)):
				out.append({"child": ref_of[child], "parent": ref_of[int(p)]})
	return out

static func _generations(parents: Array) -> int:
	var depth: Dictionary = {}
	for p in parents:
		depth[int(p["child"])] = maxi(int(depth.get(int(p["child"]), 0)), 1)
	return 2 if not depth.is_empty() else 1

## Chronicle and news lines that mention one of the members (newest last, capped).
static func history_for(members: Array) -> Array:
	var names: Array = []
	for m in members:
		names.append(str(m["name"]).split(" ")[0])
	var out: Array = []
	for line in all_chronicle():
		for n in names:
			if str(line).find(n) >= 0:
				out.append(str(line).substr(0, int(ShareClean.cap("max_line", 160))))
				break
	return out.slice(maxi(out.size() - int(ShareClean.cap("max_history", 40)), 0))

## Everything the town remembers as plain lines: the news log plus the recent chronicle notes (deduplicated, oldest first).
static func all_chronicle() -> Array:
	var out: Array = []
	for n in Story.news:
		out.append("Day %d: %s" % [int(n.get("day", 0)), str(n.get("text", ""))])
	for c in ChronicleHook.recent:
		var line := "Day %d: %s" % [int(c.get("day", 0)), str(c.get("text", ""))]
		if not out.has(line):
			out.append(line)
	return out

static func export_household(ids: Array, title: String = "") -> Dictionary:
	var raw := household(ids, title)
	var v := ShareValidate.household(raw)         # never write a file we would refuse ourselves
	if not bool(v["ok"]):
		return {"ok": false, "error": v["error"], "file": ""}
	return ShareFile.write("household", str(v["data"]["title"]), raw)

# ------------------------------------------------------------------ town
static func town_file(title: String, author: String, inbox: Array = []) -> Dictionary:
	var chron: Array = all_chronicle()
	return {"format": "sim4town", "version": 1, "title": title, "from": author, "day": SysUtil.day(),
		"save": SaveLoad.snapshot(title), "chronicle": chron.slice(maxi(chron.size() - int(ShareClean.cap("max_chronicle", 200)), 0)), "inbox": inbox}

static func export_town(title: String, author: String = "") -> Dictionary:
	if author == "":
		var res: Array = SysUtil.residents()
		author = ShareValidate.surname(str((res[0] as Folk).name)) if not res.is_empty() else "A friend"
	return ShareFile.write("town", title if title != "" else "My town", town_file(title if title != "" else "My town", author))

## Leave a gift or letter in a town file somebody exported (it is delivered when that town is loaded).
static func leave_gift(file_name: String, gift: Dictionary) -> Dictionary:
	var rd := ShareFile.read("town", file_name)
	if not bool(rd["ok"]):
		return rd
	var d: Dictionary = rd["data"]
	var inbox: Array = d.get("inbox", []) if d.get("inbox", []) is Array else []
	inbox.append(gift)
	var gv := ShareValidate.gifts(inbox)
	if not bool(gv["ok"]):
		return gv
	d["inbox"] = gv["data"]
	var path := "%s/%s" % [ShareFile.dir(), file_name]
	var fa := FileAccess.open(path, FileAccess.WRITE)
	if fa == null:
		return ShareValidate.fail("cannot write the town file")
	fa.store_string(JSON.stringify(d))
	fa.close()
	return ShareValidate.good(gv["data"])
