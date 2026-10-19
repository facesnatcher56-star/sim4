class_name StoryPursuit
extends RefCounted
## After a story nudge (StorySingles) the two keep running into each other for a couple of weeks: a call, a run-in at a shop, an invite
## to the house. Each day brings a small chance that they meet, which warms friendship and romance, so the spark can reach sweethearts.
## The pursuit is two ints kept on the pair record (saved with the relationships). Romance steps always ask RomanceRules.allowed.

static func cfg() -> Dictionary:
	return StorySingles.cfg().get("pursuit", {})

## Start (or restart) a pursuit between `f_id` and `other`.
static func begin(f_id: int, other: int) -> void:
	var p: Dictionary = RelationshipService._pair(f_id, other)
	p["pursue_until"] = SysUtil.day() + int(cfg().get("days", 14))
	p["pursue_last_invite"] = SysUtil.day()

static func active(f_id: int, other: int) -> bool:
	var p: Dictionary = RelationshipService._pair(f_id, other, false)
	return not p.is_empty() and int(p.get("pursue_until", -1)) >= SysUtil.day()

static func any_active(f_id: int) -> bool:
	for key in RelationshipService.keys_of(f_id):
		var p: Dictionary = RelationshipService.pairs[key]
		if int(p.get("pursue_until", -1)) >= SysUtil.day():
			return true
	return false

static func on_day() -> void:
	var c: Dictionary = cfg()
	if c.is_empty():
		return
	for f in SysUtil.residents():
		if SysUtil.is_away(f):
			continue
		for key in RelationshipService.keys_of(int(f.id)):
			var p: Dictionary = RelationshipService.pairs[key]
			if int(p.get("pursue_until", -1)) < SysUtil.day():
				continue
			var other: int = int(p["hi"]) if int(p["lo"]) == int(f.id) else int(p["lo"])
			if SysUtil.folk(other) != null and int(SysUtil.folk(other).id) < int(f.id):
				continue                     # two residents: handle the pair once
			_step(c, p, f, other)

static func _step(c: Dictionary, p: Dictionary, f, other: int) -> void:
	var fid: int = int(f.id)
	var townie: bool = Story.townies.has(other)
	var gone: bool = (townie and not bool(Story.townies[other]["alive"])) or (not townie and SysUtil.folk(other) == null)
	if gone or not StorySingles.is_single(fid) or not StorySingles.is_single(other) or not RomanceRules.allowed(fid, other) \
			or JusticeOrders.bars(other, fid) or RelationshipBits.has_flag(fid, other, "sweetheart"):
		p["pursue_until"] = -1               # taken, gone, or already sweethearts: the story moves on
		return
	var gap: int = int(c.get("invite_every_days", 3))
	if townie and SysUtil.day() - int(p.get("pursue_last_invite", 0)) >= gap:
		p["pursue_last_invite"] = SysUtil.day()
		StoryVisits.invite_over(other, fid)
	if not SysUtil.chance(float(c.get("meet_chance", 0.75))):
		return
	var warmth: float = 0.5 + RelationshipRomance.spark(fid, other)
	RelationshipService.add_both(fid, other, "friendship", float(c.get("friendship", 3.0)) * warmth)
	RelationshipService.add_both(fid, other, "romance", float(c.get("romance", 5.0)) * warmth)
	RelationshipService.add_history(fid, other, "chat", 0.3, fid)
	RelationshipService.touch(fid, other)
	RelationshipBits.auto_status(fid, other)
