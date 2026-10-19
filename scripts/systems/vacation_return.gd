class_name VacationReturn
extends RefCounted
## What a holiday leaves behind (task 22): the unspent spending money, work / school settled, a "vacation glow" and a rested body, a
## memory, souvenirs and photos (collections per household), stories told to friends (a gossip item + the "travel" topic) and a
## chronicle line. Called once by VacationTrip.come_back with the travellers already home.

static func cfg() -> Dictionary:
	return (Vacation.cfg().get("return", {}) as Dictionary)

static func apply(t: Dictionary) -> void:
	var k: Dictionary = cfg()
	var hid: int = int(t["hid"])
	var folks: Array = []
	for fid in t["back"]:
		var f = SysUtil.folk(int(fid))
		if f != null:
			folks.append(f)
	# money
	var wallet: int = maxi(int(t["wallet"]), 0)
	if wallet > 0:
		Economy.deposit(hid, wallet, "unspent holiday money")
	# work and school
	VacationWork.settle(t, int(t["depart_min"]), SysUtil.now())
	# mood and memory
	var days: int = int(t["days"])
	var glow: bool = days >= 1 and int(t["fun"]) >= 0
	for f2 in folks:
		f2.remove_buff("left_behind")
		if glow:
			HealthIllness.timed(f2, "vacation_glow", float(k.get("glow_hours", 36)) * 60.0)
		if days >= 2:
			HealthIllness.timed(f2, "well_rested_trip", float(k.get("rested_hours", 16)) * 60.0)
		f2.add_to_stat("energy", 25.0)
		f2.add_to_stat("fun", 20.0)
		f2.add_to_stat("social", 12.0)
		f2.remember("vacation:" + str(t["dest"]), float(k.get("memory_value", 0.7)))
		if (t["souvenirs"] as Array).size() > 0:
			HealthIllness.timed(f2, "souvenir_fond", 3.0 * 1440.0)
		if str(t["dest"]) == "cruise" and str(t.get("package_id", "")) in ["honeymoon", "anniversary"]:
			f2.add_buff("bonded_glow")
	# collections
	var sv: Array = Vacation.souvenirs.get(hid, [])
	for s in t["souvenirs"]:
		sv.append({"id": str(s["id"]), "label": str(s["label"]), "dest": str(t["dest"]), "day": SysUtil.day()})
	while sv.size() > int(k.get("souvenir_cap", 24)):
		sv.pop_front()
	Vacation.souvenirs[hid] = sv
	var ph: Array = Vacation.photos.get(hid, [])
	for p in VacationLife.photo_captions(t):
		ph.append(p)
	while ph.size() > int(k.get("photo_cap", 400)):
		ph.pop_front()
	Vacation.photos[hid] = ph
	# stories for friends
	var told: int = _tell_friends(t, folks, k)
	var names: Array = folks.map(func(x): return str(x.name))
	var text: String = "%s came home from %s with %d photos and %d souvenirs." % [", ".join(names), str(t["label"]), int(t["photos"]), (t["souvenirs"] as Array).size()]
	VacationLog.note(t, "return", text, t["back"], 2, true)
	t["summary"] = {"trip": int(t["id"]), "hid": hid, "dest": str(t["dest"]), "label": str(t["label"]), "days": days, "photos": int(t["photos"]),
		"souvenirs": (t["souvenirs"] as Array).size(), "spent": int(t["cost"]["total"]) - wallet, "refund": wallet, "told": told, "day": SysUtil.day(),
		"left_behind": (t["left"] as Array).size()}
	SysUtil.notify("Home again: %d photos, %d souvenirs. %d unspent coins came back." % [int(t["photos"]), (t["souvenirs"] as Array).size(), wallet], "good")

## Each traveller tells up to N friends (townies they know best) about the trip: a gossip item and the "travel" topic. Returns the count told.
static func _tell_friends(t: Dictionary, folks: Array, k: Dictionary) -> int:
	var told: int = 0
	var cap: int = int(k.get("story_friends", 4))
	for f in folks:
		var fid: int = int(f.id)
		var friends: Array = []
		for o in RelationshipService.all_known(fid):
			var oid: int = int(o)
			if oid == fid or not Story.townies.has(oid) or not bool(Story.townies[oid].get("alive", false)):
				continue
			friends.append([RelationshipService.value(fid, oid, "friendship"), oid])
		friends.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
		var n: int = 0
		for pr in friends:
			if n >= cap or float(pr[0]) < 5.0:
				break
			var oid2: int = int(pr[1])
			RelationshipKnowledge.note_topic(fid, oid2, str(k.get("story_topic", "travel")))
			RelationshipKnowledge.add_gossip(oid2, fid, "%s went to %s and had a wonderful time." % [f.name, str(t["label"])], "vacation")
			RelationshipService.add_both(fid, oid2, "friendship", float(k.get("friend_bonus", 3.0)))
			n += 1
			told += 1
	return told
