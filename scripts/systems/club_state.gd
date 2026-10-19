class_name ClubState
extends RefCounted
## The clubs of the community hall (task 14): book club (Tuesday evening), chess club (Thursday evening), garden club (Saturday morning). Townies fill
## each club (5 members, statistical); a resident joins for a few coins (service club_join) and goes to a meeting (club_meet) on its day: skill xp,
## company, and a little friendship with some of the townie members. A meeting also posts the club's weekly line to the chronicle.
## Tier: TOWN, weekly news; residents' meetings are events. Saved in the `life` block (`clubs`).

static var members: Dictionary = {}       # club id -> [person ids] (townies and residents)

static func reset() -> void:
	members.clear()

static func defs() -> Dictionary:
	return LifeDefs.cfg("clubs")

static func label(club: String) -> String:
	return str((defs().get(club, {}) as Dictionary).get("label", club.capitalize()))

static func ensure() -> void:
	var ids: Array = Story.alive_townies().filter(func(t): return Story.stage_of(t) in ["teen", "adult", "elder"]).map(func(t): return int(t["id"]))
	ids.sort()
	if ids.is_empty():
		return
	var offset := 0
	for club in defs():
		if not members.has(club):
			var n: int = mini(int(defs()[club].get("members", 5)), ids.size())
			members[club] = []
			for i in n:
				members[club].append(ids[(offset + i) % ids.size()])
		offset += 2

static func is_member(id: int, club: String) -> bool:
	return (members.get(club, []) as Array).has(id)

static func clubs_of(id: int) -> Array:
	return members.keys().filter(func(c): return is_member(id, str(c)))

static func join(id: int, club: String) -> void:
	if not members.has(club):
		members[club] = []
	if not is_member(id, club):
		members[club].append(id)

## A meeting: friendship with up to `friends_per_meeting` townie members.
static func meet(id: int, club: String) -> Array:
	var met: Array = []
	var gain: float = float(LifeDefs.cfg("culture").get("club", {}).get("friend_gain", 4.0))
	var cap: int = int(LifeDefs.cfg("culture").get("club", {}).get("friends_per_meeting", 2))
	for m in members.get(club, []):
		if met.size() >= cap:
			break
		if int(m) != id and Story.townies.has(int(m)) and bool(Story.townies[int(m)]["alive"]):
			RelationshipService.add_both(id, int(m), "friendship", gain)
			met.append(int(m))
	return met

## Weekly line on the club's day.
static func on_day(day: int) -> void:
	ensure()
	for club in defs():
		if SysUtil.weekday(day) == int(defs()[club].get("weekday", -1)) and not (members.get(club, []) as Array).is_empty():
			LifeNote.news("community_centre", str(defs()[club].get("news", "The club met.")))

static func to_dict() -> Dictionary:
	return {"members": members.duplicate(true)}

static func from_dict(d: Dictionary) -> void:
	reset()
	for c in (d.get("members", {}) as Dictionary):
		members[str(c)] = SysUtil.to_ints(d["members"][c])
