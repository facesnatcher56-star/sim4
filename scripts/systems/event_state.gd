class_name EventState
extends RefCounted
## Bookkeeping of the family and social events (task 14): which party a person already threw this year, which funerals were held, and the
## town-wide neighbourhood events that already ran. Saved in the `life` block (`events`).

static var last: Dictionary = {}          # "folk|kind" -> calendar year of the last such event
static var funerals: Dictionary = {}      # dead person id -> day of the funeral
static var ran: Dictionary = {}           # neighbourhood event id -> day it last ran

static func reset() -> void:
	last.clear()
	funerals.clear()
	ran.clear()

static func year_now() -> int:
	return Seasons.year_at(SysUtil.day())

static func done_this_year(fid: int, kind: String) -> bool:
	return int(last.get("%d|%s" % [fid, kind], -1)) == year_now()

static func mark(fid: int, kind: String) -> void:
	last["%d|%s" % [fid, kind]] = year_now()

## Friends and family who can come: contacts (residents or townies) who are reachable, best friends first.
static func guests(fid: int, n: int, min_friendship: float, exclude: Array = []) -> Array:
	var out: Array = []
	for c in PhoneCmd.contacts(fid, 40):
		if out.size() >= n:
			break
		if float(c["friendship"]) < min_friendship or str(c["reason"]) != "" or exclude.has(int(c["id"])) or EduState.stage_of(int(c["id"])) in ["baby"]:
			continue
		out.append(int(c["id"]))
	return out

static func to_dict() -> Dictionary:
	return {"last": last.duplicate(), "funerals": SysUtil.str_keys(funerals), "ran": ran.duplicate()}

static func from_dict(d: Dictionary) -> void:
	reset()
	for k in (d.get("last", {}) as Dictionary):
		last[str(k)] = int(d["last"][k])
	for k2 in (d.get("funerals", {}) as Dictionary):
		funerals[int(str(k2))] = int(d["funerals"][k2])
	for k3 in (d.get("ran", {}) as Dictionary):
		ran[str(k3)] = int(d["ran"][k3])
