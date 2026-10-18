class_name ShareImport
extends RefCounted
## Importing validated shared data. Households arrive as townies (fresh ids, relationships to the town reset to strangers,
## looks made distinct from everyone living here). Towns are written to a NEW save slot, never over the current game.

const MAX_TOWNIES := 40
const MAX_FAMILIES := 12

static var first_slot: int = 1          # the slots a town may be written to (tests narrow this)
static var last_slot: int = SaveSlots.SLOTS

## `data` must come from ShareValidate.household. Returns {ok, error, ids, title}.
static func household(data: Dictionary) -> Dictionary:
	if data.get("format", "") != "sim4household":
		return ShareValidate.fail("not a validated household")
	var members: Array = data["members"]
	if Story.alive_townies().size() + members.size() > MAX_TOWNIES:
		return ShareValidate.fail("the town is full: nobody else can move in right now")
	if ShareState.families.size() >= MAX_FAMILIES:
		return ShareValidate.fail("too many families have already moved in")
	if Story.next_id <= 0:
		Story.next_id = int(Story.cfg().get("first_id", 1000))
	var g := RandomNumberGenerator.new()
	g.seed = SysUtil.rng.randi()               # one draw from the sim stream: the same file + the same seed imports identically
	var fkey := ShareState.new_family_key()
	var lot := _roomiest_lot()
	var id_of: Dictionary = {}
	for m in members:
		var id: int = Story.next_id
		Story.next_id += 1
		id_of[int(m["ref"])] = id
		var ap: Dictionary = GeneticsUnique.make_distinct(m["appearance"], GeneticsUnique.registry(), g)
		Story.townies[id] = {"id": id, "name": _free_name(str(m["name"]), g), "traits": (m["traits"] as Array).duplicate(), "age_days": float(m["age_days"]),
			"career": str(m["career"]), "level": int(m["level"]), "coins": 150 + 40 * int(m["level"]), "alive": true, "lot": lot, "last_visit_day": -99,
			"appearance": ap, "shared": {"family": fkey, "skills": (m["skills"] as Dictionary).duplicate(true), "aspiration": str(m["aspiration"]),
				"memories": (m["memories"] as Array).duplicate(true), "birth_doy": int(m["birth_doy"])}}
		var dpy: int = maxi(int(Aging.days_per_year()), 1)
		var born: int = SysUtil.day() - int(m["age_days"])
		born -= posmod(born - int(m["birth_doy"]), dpy)
		Family.note_person(id, str(Story.townies[id]["name"]), born)
	for r in data["relations"]:
		var a: int = id_of[int(r["a"])]
		var b: int = id_of[int(r["b"])]
		RelationshipService.add_both(a, b, "friendship", float(r["friendship"]))
		if float(r["romance"]) != 0.0:
			RelationshipService.add_both(a, b, "romance", float(r["romance"]))
		if str(r["kind"]) != "friend":
			RelationshipBits.set_flag(a, b, str(r["kind"]), true, false)
		if str(r["kind"]) == "spouse":
			Family.spouses[a] = b
			Family.spouses[b] = a
	for p in data["parents"]:
		Family.link_parent(id_of[int(p["child"])], id_of[int(p["parent"])], false, true)
	var title: String = str(data["title"])
	ShareState.families[fkey] = {"title": title, "history": (data["history"] as Array).duplicate(), "legacy": (data["legacy"] as Dictionary).duplicate(), "day": SysUtil.day()}
	var ids: Array = id_of.values()
	var line := "The %s moved to town." % title.trim_prefix("The ")
	Story._log(line)
	ChronicleHook.note("moved_in", line, ids, "town:%d" % lot, 2, true)
	SysUtil.notify(line, "story")
	return ShareValidate.good({"ids": ids, "title": title, "family": fkey})

## The lot (1..6) with the fewest townies.
static func _roomiest_lot() -> int:
	var count: Dictionary = {}
	for t in Story.alive_townies():
		count[int(t.get("lot", 1))] = int(count.get(int(t.get("lot", 1)), 0)) + 1
	var best := 1
	for lot in range(1, 7):
		if int(count.get(lot, 0)) < int(count.get(best, 0)):
			best = lot
	return best

static func _name_taken(nm: String) -> bool:
	for t in Story.townies.values():
		if str(t["name"]) == nm:
			return true
	for f in WorldIface.all_folk():
		if str(f.name) == nm:
			return true
	return false

## Keeps the name unless somebody here already has it; then the first name is swapped for one from the town's name pool.
static func _free_name(nm: String, g: RandomNumberGenerator) -> String:
	if not _name_taken(nm):
		return nm
	var last := ShareValidate.surname(nm)
	var pool: Array = Story.cfg().get("first_names", ["Sam"])
	for _i in 30:
		var cand := "%s %s" % [str(pool[g.randi_range(0, pool.size() - 1)]), last]
		if not _name_taken(cand):
			return cand
	return "%s %d" % [nm, Story.next_id]

# ------------------------------------------------------------------ town
## `data` must come from ShareValidateTown.town. `slot` = 0 picks the first empty slot. Never overwrites a used slot.
static func town(data: Dictionary, slot: int = 0) -> Dictionary:
	if data.get("format", "") != "sim4town":
		return ShareValidate.fail("not a validated town")
	if slot <= 0:
		for s in range(first_slot, last_slot + 1):
			if not SaveSlots.has_slot(s):
				slot = s
				break
	if slot <= 0:
		return ShareValidate.fail("all save slots are full: delete one first")
	if SaveSlots.has_slot(slot):
		return ShareValidate.fail("that save slot is already in use")
	var save: Dictionary = (data["save"] as Dictionary).duplicate(true)
	var sy: Dictionary = save["systems"]
	sy["share"] = {"inbox": data["inbox"], "received": [], "families": {}, "town_title": data["title"], "next_family": 1}
	_merge_chronicle(sy, data["chronicle"])
	save["label"] = "%s (shared)" % data["title"]
	DirAccess.make_dir_recursive_absolute(SaveLoad.DIR)
	var fa := FileAccess.open(SaveLoad.path(slot), FileAccess.WRITE)
	if fa == null:
		return ShareValidate.fail("cannot write the save slot")
	fa.store_string(JSON.stringify(save))
	fa.close()
	return ShareValidate.good({"slot": slot, "gifts": (data["inbox"] as Array).size()})

## Chronicle lines "Day N: text" that the town's news does not have yet are added (news keeps the newest 60).
static func _merge_chronicle(sy: Dictionary, lines: Array) -> void:
	var story: Dictionary = sy.get("story", {})
	var news: Array = story.get("news", [])
	var have: Dictionary = {}
	for n in news:
		have[str(n.get("text", ""))] = true
	for l in lines:
		var s := str(l)
		var p := s.find(": ")
		if p < 5 or not s.begins_with("Day ") or not s.substr(4, p - 4).is_valid_int():
			continue
		var text := s.substr(p + 2)
		if not have.has(text):
			have[text] = true
			news.append({"day": ShareClean.clampi_(int(s.substr(4, p - 4)), 0, 1000000), "text": text})
	news.sort_custom(func(a, b): return int(a["day"]) < int(b["day"]))
	story["news"] = news.slice(maxi(news.size() - 60, 0))
	sy["story"] = story
