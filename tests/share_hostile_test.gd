extends RefCounted
## Sharing, untrusted files: oversized, corrupt, wrong types, unknown version / fields, path traversal, huge arrays, NaN / inf,
## negative numbers, extreme names and markup are rejected or cleaned; nothing from a file is trusted as an id.

const K = preload("res://tests/systems_kit.gd")
const S = preload("res://tests/share_kit.gd")

func run() -> Array:
	var f: Array = []
	S.prepare()
	S.world()
	_files(f)
	_household(f)
	_gifts(f)
	_town(f)
	_cards(f)
	S.finish()
	K.teardown()
	return f

func _bad(f: Array, raw: Variant, why: String) -> void:
	K.expect(f, not bool(ShareValidate.household(raw)["ok"]), "household rejected: " + why)

func _files(f: Array) -> void:
	for nm in ["../evil.sim4household", "a/b.sim4household", "..\\x.sim4household", "C:\\x.sim4household", "x.exe", "", "x.sim4household.exe", "%2e%2e.sim4household"]:
		K.expect(f, not bool(ShareFile.read("household", nm)["ok"]), "file name refused: '%s'" % nm)
	var fa := FileAccess.open(S.TMP + "/big.sim4household", FileAccess.WRITE)
	fa.store_string(" ".repeat(int(ShareClean.cap("max_household_bytes")) + 10))
	fa.close()
	K.expect(f, not bool(ShareFile.read("household", "big.sim4household")["ok"]), "oversized file refused before parsing")
	var fb := FileAccess.open(S.TMP + "/junk.sim4household", FileAccess.WRITE)
	fb.store_string("{not json")
	fb.close()
	K.expect(f, not bool(ShareFile.read("household", "junk.sim4household")["ok"]), "corrupt JSON refused")
	var fc := FileAccess.open(S.TMP + "/arr.sim4household", FileAccess.WRITE)
	fc.store_string("[1,2,3]")
	fc.close()
	K.expect(f, not bool(ShareFile.read("household", "arr.sim4household")["ok"]), "a JSON array is not a household")
	K.expect(f, ShareFile.stem("../../Evil name!") == "Evil_name", "file stems are plain: %s" % ShareFile.stem("../../Evil name!"))
	var w := ShareFile.write("household", "../../x", {"a": 1})
	K.expect(f, bool(w["ok"]) and str(w["file"]) == "x.sim4household", "writes stay in the folder: %s" % w["file"])

func _household(f: Array) -> void:
	var good := S.raw_household()
	K.expect(f, bool(ShareValidate.household(good)["ok"]), "control: a good household passes")
	_bad(f, [], "array")
	_bad(f, "text", "string")
	var d := good.duplicate(true)
	d["version"] = 99
	_bad(f, d, "newer version")
	d = good.duplicate(true)
	d["version"] = 0
	_bad(f, d, "version 0")
	d = good.duplicate(true)
	d.erase("version")
	_bad(f, d, "no version")
	d = good.duplicate(true)
	d["format"] = "sim4town"
	_bad(f, d, "wrong format")
	d = good.duplicate(true)
	d["script"] = "extends Node"
	_bad(f, d, "unknown top field")
	d = good.duplicate(true)
	d["members"][0]["is_admin"] = true
	_bad(f, d, "unknown member field")
	d = good.duplicate(true)
	d["members"][0]["appearance"]["evil"] = 1
	_bad(f, d, "unknown look field")
	d = good.duplicate(true)
	d["members"][0]["appearance"]["skin"] = "red; drop"
	_bad(f, d, "bad colour")
	d = good.duplicate(true)
	d["members"][0]["traits"] = "glutton"
	_bad(f, d, "traits as string")
	d = good.duplicate(true)
	d["members"][0]["traits"] = ["not_a_trait"]
	_bad(f, d, "unknown trait")
	d = good.duplicate(true)
	d["members"][0]["skills"] = {"hacking": {"level": 3}}
	_bad(f, d, "unknown skill")
	d = good.duplicate(true)
	d["members"][0]["aspiration"] = "world_domination"
	_bad(f, d, "unknown aspiration")
	d = good.duplicate(true)
	d["members"][0]["appearance"] = []
	_bad(f, d, "appearance as array")
	d = good.duplicate(true)
	d["members"][1]["ref"] = d["members"][0]["ref"]
	_bad(f, d, "duplicate refs")
	d = good.duplicate(true)
	d["members"][0]["age_days"] = NAN
	_bad(f, d, "NaN age")
	d = good.duplicate(true)
	d["members"][0]["age_days"] = INF
	_bad(f, d, "inf age")
	d = good.duplicate(true)
	d["members"][0]["age_days"] = 1.0e12
	_bad(f, d, "huge age")
	d = good.duplicate(true)
	d["members"][0]["age_days"] = "old"
	_bad(f, d, "age as text")
	d = good.duplicate(true)
	d["relations"][0]["a"] = 77
	_bad(f, d, "relationship to nobody")
	d = good.duplicate(true)
	d["relations"][0]["kind"] = "nemesis"
	_bad(f, d, "unknown relationship kind")
	d = good.duplicate(true)
	d["parents"][0]["child"] = d["parents"][0]["parent"]
	_bad(f, d, "own parent")
	d = good.duplicate(true)
	d["history"] = ["x"].duplicate()
	for i in 50:
		d["history"].append("line %d" % i)
	_bad(f, d, "huge history array")
	d = good.duplicate(true)
	d["members"] = []
	for i in 9:
		var m: Dictionary = good["members"][0].duplicate(true)
		m["ref"] = i + 1
		d["members"].append(m)
	_bad(f, d, "nine members")
	d = good.duplicate(true)
	var deep: Variant = "x"
	for i in 40:
		deep = [deep]
	d["history"] = deep
	_bad(f, d, "nesting bomb")
	# cleaned, not rejected
	d = good.duplicate(true)
	d["members"][0]["age_days"] = -50
	d["members"][0]["name"] = "<b>[color=red]Eve[/color]</b> " + "x".repeat(100)
	d["members"][0]["skills"] = {"cooking": {"level": 999, "xp": -5}}
	d["members"][0]["appearance"]["height"] = 50
	d["members"][0]["appearance"]["hair_style"] = 9999
	d["title"] = "Fine\u0000\u0007 title " + "T".repeat(300)
	var v := ShareValidate.household(d)
	K.expect(f, bool(v["ok"]), "hostile but fixable values are cleaned: %s" % v["error"])
	if bool(v["ok"]):
		var m0: Dictionary = v["data"]["members"][0]
		var nm := str(m0["name"])
		K.expect(f, nm.length() <= 32 and nm.find("<") < 0 and nm.find("[") < 0 and nm.find("/") < 0 and nm.find("..") < 0, "name is sanitised and short: '%s'" % nm)
		K.expect(f, float(m0["age_days"]) == 0.0, "negative age is clamped")
		K.expect(f, int(m0["skills"]["cooking"]["level"]) == Folk.MAX_SKILL_LEVEL and float(m0["skills"]["cooking"]["xp"]) == 0.0, "skills are clamped")
		K.expect(f, float(m0["appearance"]["height"]) <= 1.15 and int(m0["appearance"]["hair_style"]) < int(GeneticsLook.counts()["hair_style"]), "look values are clamped")
		var title := str(v["data"]["title"])
		K.expect(f, title.length() <= 48 and title.find("\u0000") < 0 and title.find("\u0007") < 0 and title.find("/") < 0, "title is clean: '%s'" % title)
		# nothing in the data keeps an id from the file
		var before: int = Story.townies.size()
		var r := ShareImport.household(v["data"])
		K.expect(f, bool(r["ok"]) and Story.townies.size() == before + 3, "the cleaned household imports")
		for id in r["data"]["ids"]:
			K.expect(f, int(id) >= 1000, "ids never come from the file")
	d = good.duplicate(true)
	d["members"][0]["name"] = "Eve ../../etc/passwd"
	_bad(f, d, "path traversal in a name")
	d = good.duplicate(true)
	d["title"] = "res://main.tscn"
	_bad(f, d, "engine path in a title")
	d = good.duplicate(true)
	d["members"][0]["name"] = "x".repeat(5000)
	_bad(f, d, "extremely long name")
	var fake_ids := good.duplicate(true)
	fake_ids["members"][0]["id"] = 1
	_bad(f, fake_ids, "an id field is not allowed")

func _gifts(f: Array) -> void:
	var ok := ShareValidate.gifts([{"from": "Pat", "kind": "coins", "coins": 10000000}])
	K.expect(f, bool(ok["ok"]) and int(ok["data"][0]["coins"]) == 500, "coin gifts are capped at 500")
	K.expect(f, not bool(ShareValidate.gifts([{"from": "Pat", "kind": "coins", "coins": "lots"}])["ok"]), "coins must be a number")
	var neg := ShareValidate.gifts([{"from": "Pat", "kind": "coins", "coins": -50}])
	K.expect(f, bool(neg["ok"]) and (neg["data"] as Array).is_empty(), "negative coins give nothing")
	K.expect(f, not bool(ShareValidate.gifts([{"from": "Pat", "kind": "object", "object": "stove"}])["ok"]), "objects outside the allowlist are refused")
	K.expect(f, not bool(ShareValidate.gifts([{"from": "Pat", "kind": "object", "object": "../../x"}])["ok"]), "object path traversal refused")
	K.expect(f, bool(ShareValidate.gifts([{"from": "Pat", "kind": "object", "object": "plant"}])["ok"]), "allowlisted object passes")
	var lt := ShareValidate.gifts([{"from": "<i>Pat</i>", "kind": "letter", "text": "Hi [url]x[/url] <script>" + "a".repeat(3000)}])
	K.expect(f, bool(lt["ok"]) and str(lt["data"][0]["text"]).length() <= 500 and str(lt["data"][0]["text"]).find("<") < 0 and str(lt["data"][0]["from"]) == "iPati", "letters are cut to 500 characters and cleaned: %s" % str(lt["data"]))
	K.expect(f, not bool(ShareValidate.gifts([{"from": "P", "kind": "magic"}])["ok"]), "unknown gift kind refused")
	K.expect(f, not bool(ShareValidate.gifts([{"from": "P", "kind": "letter", "text": "x", "run": "code"}])["ok"]), "unknown gift field refused")
	var many: Array = []
	for i in 20:
		many.append({"from": "P", "kind": "letter", "text": "hello"})
	K.expect(f, not bool(ShareValidate.gifts(many)["ok"]), "too many gifts refused")

func _town_raw() -> Dictionary:
	return ShareExport.town_file("Vale town", "Vale", [])

func _town(f: Array) -> void:
	var good := _town_raw()
	var v := ShareValidateTown.town(good)
	K.expect(f, bool(v["ok"]), "control: our own town file validates: %s" % v["error"])
	var d := good.duplicate(true)
	d["save"]["version"] = SaveLoad.VERSION + 1
	K.expect(f, not bool(ShareValidateTown.town(d)["ok"]), "newer save version refused")
	d = good.duplicate(true)
	d["save"]["version"] = SaveLoad.VERSION - 1
	K.expect(f, not bool(ShareValidateTown.town(d)["ok"]), "old save version refused")
	d = good.duplicate(true)
	d["save"]["autorun"] = "x"
	K.expect(f, not bool(ShareValidateTown.town(d)["ok"]), "unknown save field refused")
	d = good.duplicate(true)
	d["save"]["systems"]["backdoor"] = {}
	K.expect(f, not bool(ShareValidateTown.town(d)["ok"]), "unknown system refused")
	d = good.duplicate(true)
	d["save"]["folk"][0]["tile"] = "here"
	K.expect(f, not bool(ShareValidateTown.town(d)["ok"]), "folk with a bad position refused")
	d = good.duplicate(true)
	d["save"]["folk"][0]["name"] = {"x": 1}
	K.expect(f, not bool(ShareValidateTown.town(d)["ok"]), "folk with a bad name refused")
	d = good.duplicate(true)
	d["save"]["folk"][0]["needs"] = {"hunger": INF}
	K.expect(f, not bool(ShareValidateTown.town(d)["ok"]), "infinite need refused")
	d = good.duplicate(true)
	d["save"]["world"]["note"] = "see ../../secrets and res://main.gd"
	K.expect(f, not bool(ShareValidateTown.town(d)["ok"]), "path traversal strings inside the save refused")
	d = good.duplicate(true)
	var deep: Variant = 1
	for i in 40:
		deep = {"a": deep}
	d["save"]["world"]["deep"] = deep
	K.expect(f, not bool(ShareValidateTown.town(d)["ok"]), "nesting bomb refused")
	d = good.duplicate(true)
	d["save"]["systems"]["share"] = {"inbox": [{"from": "x", "kind": "coins", "coins": 500}]}
	var sv := ShareValidateTown.town(d)
	K.expect(f, bool(sv["ok"]) and not sv["data"]["save"]["systems"].has("share"), "gifts hidden inside the save are dropped")
	d = good.duplicate(true)
	d["inbox"] = [{"from": "x", "kind": "coins", "coins": 99999}]
	var iv := ShareValidateTown.town(d)
	K.expect(f, bool(iv["ok"]) and int(iv["data"]["inbox"][0]["coins"]) == 500, "envelope gifts are bounded")
	d = good.duplicate(true)
	d["save"]["folk"][0]["name"] = "<b>Evil</b>[color=red]"
	var nv := ShareValidateTown.town(d)
	K.expect(f, bool(nv["ok"]) and str(nv["data"]["save"]["folk"][0]["name"]).find("<") < 0, "folk names in a town are sanitised")

func _cards(f: Array) -> void:
	var card := ShareCards.for_ids(S.ids_of_household(), "The Vale family")
	K.expect(f, not card.is_empty() and str(card["format"]) == "sim4card" and (card["lines"] as Array).size() >= 2, "a card is made: %s" % str(card.get("lines", [])))
	var cv := ShareCards.validate(card)
	K.expect(f, bool(cv["ok"]), "our card validates: %s" % cv["error"])
	var bad := card.duplicate(true)
	bad["lines"] = "no"
	K.expect(f, not bool(ShareCards.validate(bad)["ok"]), "a card with bad lines is refused")
	bad = card.duplicate(true)
	bad["x"] = 1
	K.expect(f, not bool(ShareCards.validate(bad)["ok"]), "a card with unknown fields is refused")
	var w := ShareCards.export_json(card)
	K.expect(f, bool(w["ok"]) and str(w["file"]).ends_with(".sim4card"), "a card exports as a .sim4card file")
