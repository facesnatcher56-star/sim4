extends RefCounted
## Sharing, households: export -> file -> validate -> import equals the data (modulo id remap and relationship reset), looks stay
## unique, strangers stay strangers, the same file + the same seed imports identically.

const K = preload("res://tests/systems_kit.gd")
const S = preload("res://tests/share_kit.gd")

func run() -> Array:
	var f: Array = []
	S.prepare()
	_roundtrip(f)
	_determinism(f)
	_limits(f)
	S.finish()
	K.teardown()
	return f

func _file_data(f: Array) -> Dictionary:
	var r := ShareExport.export_household(S.ids_of_household(), "The Vale family")
	K.expect(f, bool(r["ok"]), "export writes a file: %s" % r["error"])
	K.expect(f, str(r["file"]).ends_with(".sim4household"), "household files use the .sim4household extension: %s" % r["file"])
	var rd := ShareFile.read("household", str(r["file"]))
	K.expect(f, bool(rd["ok"]), "the file reads back")
	var v := ShareValidate.household(rd["data"])
	K.expect(f, bool(v["ok"]), "our own file validates: %s" % v["error"])
	return v["data"] if bool(v["ok"]) else {}

func _roundtrip(f: Array) -> void:
	S.world()
	var raw := S.raw_household()
	var d := _file_data(f)
	if d.is_empty():
		return
	K.expect(f, (d["members"] as Array).size() == 3 and str(d["title"]) == "The Vale family", "three members and the title survive")
	var ann_src = SysUtil.residents()[0]
	var m0: Dictionary = d["members"][0]
	K.expect(f, str(m0["name"]) == "Ann Vale" and (m0["traits"] as Array) == ann_src.traits, "name and traits survive: %s" % str(m0["traits"]))
	K.expect(f, int(m0["skills"].get("cooking", {}).get("level", 0)) == int(ann_src.skills["cooking"]["level"]), "skills survive")
	K.expect(f, str(m0["aspiration"]) == "master_chef", "aspiration survives")
	K.expect(f, (m0["memories"] as Array).size() == 1 and str(m0["memories"][0]["key"]) == "good_meal", "key memories survive")
	var diffs: Array = []
	K.expect(f, K.deep_eq(m0["appearance"], Genetics.normalize(ann_src.appearance), "ap", diffs), "appearance survives exactly: %s" % str(diffs.slice(0, 3)))
	K.expect(f, (d["relations"] as Array).size() == 3 and (d["parents"] as Array).size() == 2, "relationships among members and family links survive")
	K.expect(f, (d["history"] as Array).size() == 2, "chronicle lines about them travel along: %d" % (d["history"] as Array).size())
	# import into the same town: fresh ids, strangers to everyone else, distinct looks
	var townies_before: Array = Story.townies.keys()
	var taken: Dictionary = {}
	for id in townies_before:
		taken[int(id)] = true
	var rels_before: int = RelationshipService.pairs.size()
	var r := ShareImport.household(d)
	K.expect(f, bool(r["ok"]), "import works: %s" % r["error"])
	var ids: Array = r["data"]["ids"]
	K.expect(f, ids.size() == 3 and Story.townies.size() == townies_before.size() + 3, "three new townies")
	for id2 in ids:
		K.expect(f, not taken.has(int(id2)) and int(id2) >= 1000, "ids are fresh (%d)" % int(id2))
		var t: Dictionary = Story.townies[int(id2)]
		K.expect(f, bool(t["alive"]) and int(t["lot"]) >= 1 and int(t["lot"]) <= 6, "settled on a lot")
		K.expect(f, GeneticsUnique.is_distinct(t["appearance"], GeneticsUnique.registry_without(t["appearance"])), "the look of %s is unique in town" % t["name"])
	var names: Array = []
	for id3 in ids:
		names.append(str(Story.townies[int(id3)]["name"]))
	K.expect(f, names.size() == 3, "names kept or made unique: %s" % str(names))
	var a: int = ids[0]
	var b: int = ids[1]
	K.expect(f, RelationshipService.knows(a, b) and RelationshipService.pairs[SysUtil.pair_key(a, b)]["flags"].get("spouse", false), "the couple is still married")
	K.expect(f, RelationshipService.pairs.size() == rels_before + 3, "only the three relationships between members were added")
	var strangers := true
	for tid in townies_before:
		for id4 in ids:
			if RelationshipService.knows(int(tid), int(id4)):
				strangers = false
	K.expect(f, strangers, "nobody in town knows the newcomers yet")
	K.expect(f, (Family.parents.get(ids[2], []) as Array).size() == 2, "the child's parents are linked")
	K.expect(f, str(Story.townies[a]["shared"]["aspiration"]) == "master_chef" and not ShareState.families.is_empty(), "stories (aspiration, history) are kept")
	K.expect(f, Story.news.back()["text"] == "The Vale family moved to town.", "a news line announces them: %s" % str(Story.news.back()))
	var chron_line := false
	for c in ChronicleHook.recent:
		if str(c["kind"]) == "moved_in":
			chron_line = true
	K.expect(f, chron_line, "a chronicle line is noted")
	# exporting a townie family again works too
	var again := ShareExport.households()
	var townie_groups := 0
	for e in again:
		if bool(e["townies"]):
			townie_groups += 1
	K.expect(f, townie_groups >= 1, "townie families can be exported")
	var tf := ShareExport.export_household(ids, "Again")
	K.expect(f, bool(tf["ok"]), "an imported family can be exported again: %s" % tf["error"])
	K.teardown()

func _imported(seed_value: int) -> Dictionary:
	S.world(seed_value)
	var v := ShareValidate.household(S.raw_household())
	SysUtil.seed_rng(99)
	var r := ShareImport.household(v["data"])
	var out: Dictionary = {}
	for id in r["data"]["ids"]:
		out[int(id)] = (Story.townies[int(id)] as Dictionary).duplicate(true)
	K.teardown()
	return out

func _determinism(f: Array) -> void:
	var one := _imported(321)
	var two := _imported(321)
	var diffs: Array = []
	K.expect(f, one.size() == 3 and K.deep_eq(one, two, "imp", diffs), "the same file with the same seed imports identically: %s" % str(diffs.slice(0, 3)))

func _limits(f: Array) -> void:
	S.world()
	var d: Dictionary = ShareValidate.household(S.raw_household())["data"]
	var cnt := 0
	for i in 13:
		var r := ShareImport.household(d)
		if bool(r["ok"]):
			cnt += 1
	K.expect(f, cnt < 13 and ShareState.families.size() <= ShareImport.MAX_FAMILIES, "the town does not fill up forever (%d imports allowed)" % cnt)
	K.teardown()
