class_name ShareValidate
extends RefCounted
## Strict validation of shared household / town / card / gift data. Every function returns {ok, error, data}: `data` is a
## NEW dictionary built only from known fields (unknown fields, wrong types, NaN / inf are rejected; numbers are clamped; text
## is sanitised). Ids in the file are only labels (`ref`) and are remapped by ShareImport.

static func fail(msg: String) -> Dictionary:
	return {"ok": false, "error": msg, "data": {}}

static func good(d: Variant) -> Dictionary:
	return {"ok": true, "error": "", "data": d}

static func unknown_key(d: Dictionary, allowed: Array) -> String:
	for k in d:
		if not (k is String) or not allowed.has(k):
			return str(k).substr(0, 24)
	return ""

static func check_head(raw: Variant, fmt: String, keys_cap: String) -> String:
	if not (raw is Dictionary):
		return "this is not a Sim 4 file"
	var d: Dictionary = raw
	if str(d.get("format", "")) != fmt:
		return "this is not a %s file" % fmt
	if not ShareClean.is_whole(d.get("version", null)):
		return "the file has no version"
	var ver: int = int(d["version"])
	if ver > int(ShareClean.cap("format_version", 1)):
		return "this file is from a newer version of the game"
	if ver < 1:
		return "this file is too old to read"
	var u := unknown_key(d, ShareClean.cap(keys_cap, []))
	if u != "":
		return "unexpected field '%s'" % u
	return ""

# ------------------------------------------------------------------ household
static func household(raw: Variant) -> Dictionary:
	var e := check_head(raw, "sim4household", "household_keys")
	if e != "":
		return fail(e)
	var scan := ShareClean.scan(raw)
	if scan != "":
		return fail(scan)
	var d: Dictionary = raw
	var members_raw: Variant = d.get("members", null)
	if not (members_raw is Array) or (members_raw as Array).is_empty():
		return fail("the household has no members")
	if (members_raw as Array).size() > int(ShareClean.cap("max_members", 8)):
		return fail("too many members")
	var members: Array = []
	var refs: Dictionary = {}
	for m in members_raw:
		var r := _member(m)
		if not bool(r["ok"]):
			return r
		var md: Dictionary = r["data"]
		if refs.has(md["ref"]):
			return fail("two members share a reference")
		refs[md["ref"]] = true
		members.append(md)
	var out: Dictionary = {"format": "sim4household", "version": 1, "members": members}
	out["title"] = ShareClean.text(d.get("title", ""), int(ShareClean.cap("max_title", 48)))
	if out["title"] == "":
		out["title"] = "The %s family" % surname(members[0]["name"])
	out["day"] = ShareClean.clampi_(d.get("day", 0), 0, 1000000)
	var rel_r := _relations(d.get("relations", []), refs)
	if not bool(rel_r["ok"]):
		return rel_r
	out["relations"] = rel_r["data"]
	var par_r := _parents(d.get("parents", []), refs)
	if not bool(par_r["ok"]):
		return par_r
	out["parents"] = par_r["data"]
	var hist_r := lines(d.get("history", []), int(ShareClean.cap("max_history", 40)))
	if not bool(hist_r["ok"]):
		return hist_r
	out["history"] = hist_r["data"]
	var leg: Variant = d.get("legacy", {})
	if not (leg is Dictionary):
		return fail("the legacy is malformed")
	var lu := unknown_key(leg, ["members", "oldest_days", "generations", "children"])
	if lu != "":
		return fail("unexpected legacy field '%s'" % lu)
	out["legacy"] = {"members": members.size(), "oldest_days": ShareClean.clampf_(leg.get("oldest_days", 0), 0, 400),
		"generations": ShareClean.clampi_(leg.get("generations", 1), 1, 20, 1), "children": ShareClean.clampi_(leg.get("children", 0), 0, 50)}
	return good(out)

static func surname(full: String) -> String:
	var p: PackedStringArray = full.split(" ", false)
	return p[p.size() - 1] if p.size() > 0 else "Visitor"

static func _member(m: Variant) -> Dictionary:
	if not (m is Dictionary):
		return fail("a member is malformed")
	var d: Dictionary = m
	var u := unknown_key(d, ShareClean.cap("member_keys", []))
	if u != "":
		return fail("unexpected member field '%s'" % u)
	if not ShareClean.is_whole(d.get("ref", null)) or int(d["ref"]) < 1 or int(d["ref"]) > 99:
		return fail("a member has a bad reference")
	if not (d.get("name", null) is String):
		return fail("a member has no name")
	var nm := ShareClean.text(d["name"], int(ShareClean.cap("max_name", 32)))
	if nm == "":
		return fail("a member has an empty name")
	if not (d.get("stage", null) is String) or not Aging.stage_ids().has(d["stage"]):
		return fail("a member has an unknown life stage")
	if not ShareClean.is_num(d.get("age_days", null)):
		return fail("a member has a bad age")
	var out: Dictionary = {"ref": int(d["ref"]), "name": nm,
		"age_days": ShareClean.clampf_(d["age_days"], 0.0, float(ShareClean.cap("age_days_max", 400)))}
	out["stage"] = Aging.stage_for_days(out["age_days"])
	out["sex"] = str(d["sex"]) if Sexes.valid(d.get("sex", "")) else Sexes.guess(nm, int(d["ref"]))
	var tr: Variant = d.get("traits", [])
	if not (tr is Array) or (tr as Array).size() > int(ShareClean.cap("max_traits", 5)):
		return fail("a member has bad traits")
	var traits: Array = []
	for t in tr:
		if not (t is String) or not SimEnv.data().traits().has(t):
			return fail("a member has an unknown trait")
		if not traits.has(t):
			traits.append(t)
	out["traits"] = traits
	var ap := _appearance(d.get("appearance", null))
	if not bool(ap["ok"]):
		return ap
	out["appearance"] = ap["data"]
	var sk: Variant = d.get("skills", {})
	if not (sk is Dictionary):
		return fail("a member has bad skills")
	var skills: Dictionary = {}
	for k in sk:
		if not Folk.SKILLS.has(k) or not (sk[k] is Dictionary) or unknown_key(sk[k], ["level", "xp"]) != "":
			return fail("a member has an unknown skill")
		skills[k] = {"level": ShareClean.clampi_(sk[k].get("level", 0), 0, Folk.MAX_SKILL_LEVEL), "xp": ShareClean.clampf_(sk[k].get("xp", 0), 0.0, 100000.0)}
	out["skills"] = skills
	var asp: Variant = d.get("aspiration", "")
	if not (asp is String) or (asp != "" and not Goals.aspiration_ids().has(asp)):
		return fail("a member has an unknown aspiration")
	out["aspiration"] = asp
	var mem: Variant = d.get("memories", [])
	if not (mem is Array) or (mem as Array).size() > int(ShareClean.cap("max_memories", 5)):
		return fail("a member has too many memories")
	var memories: Array = []
	for x in mem:
		if not (x is Dictionary) or unknown_key(x, ["key", "value"]) != "" or not (x.get("key", null) is String) or not ShareClean.is_num(x.get("value", null)):
			return fail("a memory is malformed")
		var mk := ShareClean.key(x["key"], int(ShareClean.cap("max_key", 32)))
		if mk != "":
			memories.append({"key": mk, "value": ShareClean.clampf_(x["value"], -1.0, 1.0)})
	out["memories"] = memories
	var car: Variant = d.get("career", "")
	if not (car is String) or (car != "" and not Careers.career_ids().has(car)):
		car = ""
	out["career"] = car
	out["level"] = ShareClean.clampi_(d.get("level", 1), 1, 10, 1)
	out["birth_doy"] = ShareClean.clampi_(d.get("birth_doy", 0), 0, 399)
	return good(out)

static func _appearance(a: Variant) -> Dictionary:
	if not (a is Dictionary):
		return fail("a member has no look")
	var hexes := ["skin", "hair_color", "eye_color", "shirt", "pants", "color", "accent", "shoe_color"]
	var floats := ["height", "build"]
	var out: Dictionary = {}
	for k in a:
		var v = a[k]
		if hexes.has(k):
			if not ShareClean.is_hex(v):
				return fail("a look has a bad colour")
			out[k] = (v as String).to_lower()
		elif floats.has(k):
			if not ShareClean.is_num(v):
				return fail("a look has a bad size")
			out[k] = ShareClean.clampf_(v, 0.85, 1.15, 1.0)
		elif GeneticsLook.INT_KEYS.has(k):
			if not ShareClean.is_whole(v):
				return fail("a look has a bad part")
			out[k] = ShareClean.clampi_(v, 0, 30)
		else:
			return fail("unexpected look field '%s'" % str(k).substr(0, 20))
	for k2 in ["skin", "hair_color", "eye_color", "shirt", "pants", "hair_style"]:
		if not out.has(k2):
			return fail("a look is incomplete")
	out = Genetics.normalize(out)
	return good(out) if Genetics.is_valid(out) else fail("a look is incomplete")

static func _relations(raw: Variant, refs: Dictionary) -> Dictionary:
	if not (raw is Array) or (raw as Array).size() > int(ShareClean.cap("max_relations", 40)):
		return fail("too many relationships")
	var out: Array = []
	var kinds: Array = ShareClean.cap("relation_kinds", [])
	for r in raw:
		if not (r is Dictionary) or unknown_key(r, ["a", "b", "kind", "friendship", "romance"]) != "":
			return fail("a relationship is malformed")
		if not ShareClean.is_whole(r.get("a", null)) or not ShareClean.is_whole(r.get("b", null)) or not refs.has(int(r["a"])) or not refs.has(int(r["b"])) or int(r["a"]) == int(r["b"]):
			return fail("a relationship points at nobody")
		var kind: String = str(r.get("kind", "friend"))
		if not kinds.has(kind):
			return fail("a relationship has an unknown kind")
		out.append({"a": int(r["a"]), "b": int(r["b"]), "kind": kind, "friendship": ShareClean.clampf_(r.get("friendship", 0), -100.0, 100.0),
			"romance": ShareClean.clampf_(r.get("romance", 0), -100.0, 100.0)})
	return good(out)

static func _parents(raw: Variant, refs: Dictionary) -> Dictionary:
	if not (raw is Array) or (raw as Array).size() > int(ShareClean.cap("max_parents", 16)):
		return fail("too many family links")
	var out: Array = []
	for p in raw:
		if not (p is Dictionary) or unknown_key(p, ["child", "parent"]) != "":
			return fail("a family link is malformed")
		if not ShareClean.is_whole(p.get("child", null)) or not ShareClean.is_whole(p.get("parent", null)) or not refs.has(int(p["child"])) or not refs.has(int(p["parent"])) or int(p["child"]) == int(p["parent"]):
			return fail("a family link points at nobody")
		out.append({"child": int(p["child"]), "parent": int(p["parent"])})
	return good(out)

static func lines(raw: Variant, max_n: int) -> Dictionary:
	if not (raw is Array) or (raw as Array).size() > max_n:
		return fail("too many history lines")
	var out: Array = []
	for l in raw:
		if not (l is String):
			return fail("a history line is not text")
		var t := ShareClean.text(l, int(ShareClean.cap("max_line", 160)))
		if t != "":
			out.append(t)
	return good(out)

# ------------------------------------------------------------------ gifts and letters
## inbox: Array of {from, kind: coins|object|letter, coins?, object?, text?}. Bounded: counts, coins and the object allowlist.
static func gifts(raw: Variant) -> Dictionary:
	var g: Dictionary = ShareClean.cap("gift", {})
	if not (raw is Array) or (raw as Array).size() > int(g.get("max_items", 6)):
		return fail("too many gifts")
	var out: Array = []
	for x in raw:
		if not (x is Dictionary) or unknown_key(x, ["from", "kind", "coins", "object", "text"]) != "":
			return fail("a gift is malformed")
		var kind: String = str(x.get("kind", ""))
		var item: Dictionary = {"from": ShareClean.text(x.get("from", ""), int(g.get("max_from", 32))), "kind": kind}
		if item["from"] == "":
			item["from"] = "A friend"
		match kind:
			"coins":
				if not ShareClean.is_whole(x.get("coins", null)):
					return fail("a gift of coins has a bad amount")
				item["coins"] = ShareClean.clampi_(x["coins"], 0, int(g.get("max_coins", 500)))
				if int(item["coins"]) <= 0:
					continue
			"object":
				if not (x.get("object", null) is String) or not (g.get("objects", []) as Array).has(x["object"]):
					return fail("a gift object is not allowed")
				item["object"] = str(x["object"])
			"letter":
				if not (x.get("text", null) is String):
					return fail("a letter has no text")
				item["text"] = ShareClean.text(x["text"], int(g.get("max_letter", 500)))
				if item["text"] == "":
					continue
			_:
				return fail("a gift has an unknown kind")
		out.append(item)
	return good(out)
