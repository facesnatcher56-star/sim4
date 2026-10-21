class_name PhoneState
extends RefCounted
## The phone of every resident (task 14): a contact list built from the people they know, calls, texts and invitations. State only; the actions are
## PhoneCmd (player commands) and LifeOuting (going out together); PhoneDay brings invitations from friends.
##   inbox       [{id, folk, from, day, place, service, text, expires}] invitations waiting for an answer (cap 6 per person)
##   contact_log {"folk|other": {day, calls, texts}} to keep a call or text from being spammed for free friendship
##   companions  folk id -> {other, place, service, pay_both, day}: who is going out with whom right now (PlaceUse.finish_now applies it)
## Own seeded rng. Saved in the `life` block (`phone`).

const SEED := 140081

static var inbox: Array = []
static var contact_log: Dictionary = {}
static var companions: Dictionary = {}
static var next_id: int = 1
static var rng: RandomNumberGenerator = RandomNumberGenerator.new()

static func reset() -> void:
	inbox.clear()
	contact_log.clear()
	companions.clear()
	next_id = 1
	rng = RandomNumberGenerator.new()
	rng.seed = SEED
	PhoneOwn.reset()
	PhoneJobs.reset()
	JobLeads.reset()

static func cfg() -> Dictionary:
	return LifeDefs.cfg("phone")

static func inbox_of(fid: int) -> Array:
	return inbox.filter(func(m): return int(m["folk"]) == fid)

static func _key(a: int, b: int) -> String:
	return "%d|%d" % [a, b]

static func today_count(fid: int, other: int, what: String) -> int:
	var e: Dictionary = contact_log.get(_key(fid, other), {})
	return int(e.get(what, 0)) if int(e.get("day", -1)) == SysUtil.day() else 0

static func note_contact(fid: int, other: int, what: String) -> void:
	var e: Dictionary = contact_log.get(_key(fid, other), {})
	if int(e.get("day", -1)) != SysUtil.day():
		e = {"day": SysUtil.day(), "calls": 0, "texts": 0, "invites": 0}
	e[what] = int(e.get(what, 0)) + 1
	contact_log[_key(fid, other)] = e
	if contact_log.size() > 400:
		for k in contact_log.keys().slice(0, 100):
			contact_log.erase(k)

static func add_invite(fid: int, from_id: int, pid: String, sid: String, text: String) -> void:
	var mine: Array = inbox_of(fid)
	if mine.size() >= int(cfg().get("inbox_cap", 6)):
		inbox.erase(mine[0])
	inbox.append({"id": next_id, "folk": fid, "from": from_id, "day": SysUtil.day(), "place": pid, "service": sid, "text": text,
		"expires": SysUtil.day() + int(cfg().get("invite_days", 2))})
	next_id += 1

static func take(fid: int, mid: int) -> Dictionary:
	for m in inbox:
		if int(m["id"]) == mid and int(m["folk"]) == fid:
			inbox.erase(m)
			return m
	return {}

static func on_day(day: int) -> void:
	inbox = inbox.filter(func(m): return int(m["expires"]) >= day)
	for k in contact_log.keys():
		if int(contact_log[k].get("day", -1)) < day - 3:
			contact_log.erase(k)
	for fid in companions.keys():
		if int(companions[fid]["day"]) < day - 1:
			companions.erase(fid)

static func to_dict() -> Dictionary:
	return {"inbox": inbox.duplicate(true), "log": contact_log.duplicate(true), "next_id": next_id, "rng_state": str(rng.state), "own": PhoneOwn.to_dict(), "leads": JobLeads.to_dict()}

static func from_dict(d: Dictionary) -> void:
	reset()
	inbox = (d.get("inbox", []) as Array).duplicate(true)
	for m in inbox:
		for k in ["id", "folk", "from", "day", "expires"]:
			m[k] = int(m[k])
	contact_log = (d.get("log", {}) as Dictionary).duplicate(true)
	for k2 in contact_log:
		for kk in contact_log[k2]:
			contact_log[k2][kk] = int(contact_log[k2][kk])
	next_id = int(d.get("next_id", 1))
	PhoneOwn.from_dict(d.get("own", {}))
	JobLeads.from_dict(d.get("leads", {}))
	if d.has("rng_state"):
		rng.state = int(str(d["rng_state"]))
