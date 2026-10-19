class_name WorksUnion
extends RefCounted
## Unions of the industrial careers (task 31). A resident joins by command (WorksCmd) and pays dues out of each shift's pay; in a strike a member
## gets strike pay instead of nothing. Townies are members by a fixed share (id based, nothing stored). Numbers: data/careers_works.json works.union.

static var members: Dictionary = {}       # folk id -> career joined under

static func reset() -> void:
	members.clear()

static func _c() -> Dictionary:
	return Works.cfg().get("union", {})

static func is_member(fid: int) -> bool:
	if not members.has(fid):
		return false
	return Careers.career_of(fid) == str(members[fid])

static func townie_member(t: Dictionary) -> bool:
	return Works.is_works(str(t.get("career", ""))) and (int(t.get("id", 0)) * 37) % 100 < int(float(_c().get("townie_share", 0.35)) * 100.0)

static func join(f) -> Dictionary:
	var cid: String = Careers.career_of(int(f.id))
	if not Works.is_works(cid):
		return {"ok": false, "msg": "Only industrial workers have a union to join."}
	if is_member(int(f.id)):
		return {"ok": false, "msg": "Already a member."}
	members[int(f.id)] = cid
	SysUtil.notify(Works.fill("union_join", {"name": f.name, "sector": Works.sector_label(cid)}), "career")
	return {"ok": true, "msg": ""}

static func leave(f) -> Dictionary:
	if not members.has(int(f.id)):
		return {"ok": false, "msg": "Not a member."}
	members.erase(int(f.id))
	SysUtil.notify(Works.fill("union_leave", {"name": f.name}), "career")
	return {"ok": true, "msg": ""}

static func dues(pay: int) -> int:
	return int(round(float(pay) * float(_c().get("dues_share", 0.02))))

## Strike pay for a day of an 8-hour shift.
static func strike_pay(hourly: int) -> int:
	return int(round(float(hourly) * 8.0 * float(_c().get("strike_pay_share", 0.4))))

static func on_day() -> void:
	for fid in members.keys():
		if not is_member(int(fid)):
			members.erase(fid)

static func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for fid in members:
		out[str(fid)] = members[fid]
	return out

static func from_dict(d: Dictionary) -> void:
	members.clear()
	for k in d:
		members[int(k)] = str(d[k])
