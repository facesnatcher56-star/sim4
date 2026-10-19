class_name IncidentSubject
extends RefCounted
## Who (or what lot) an incident is about, with ONE view for conditions / risk multipliers whether the subject is a real
## Folk (FULL resolution) or a far Story townie record (STATISTICAL resolution).
##   kind "folk"   - a real Folk (household member or a visitor / guest that is on the map right now)
##   kind "townie" - a Story townie that is not on the map as a Folk
##   kind "lot"    - a household lot (key "home:<hid>", full) or a townie lot (key "town:<n>", statistical)
## Townie skills come from their career (a cook has cooking = level + 1), needs / buffs are optional keys of the record.

const CAREER_SKILL := {"cook": "cooking", "coder": "logic", "painter": "painting", "fitness_coach": "fitness"}

var kind: String = "folk"
var id: int = -1                    # folk id / townie id / household id or townie lot number
var folk = null
var lot_key: String = ""
var household_id: int = 0

static func of_folk(f) -> IncidentSubject:
	var s := IncidentSubject.new()
	s.kind = "folk"
	s.folk = f
	s.id = int(f.id)
	s.household_id = int(f.household_id)
	s.lot_key = ("home:%d" % s.household_id) if s.household_id > 0 else ""
	return s

static func of_townie(tid: int) -> IncidentSubject:
	var s := IncidentSubject.new()
	s.kind = "townie"
	s.id = tid
	s.lot_key = "town:%d" % int((Story.townies.get(tid, {}) as Dictionary).get("lot", 0))
	return s

static func of_household(hid: int) -> IncidentSubject:
	var s := IncidentSubject.new()
	s.kind = "lot"
	s.id = hid
	s.household_id = hid
	s.lot_key = "home:%d" % hid
	return s

static func of_town_lot(n: int) -> IncidentSubject:
	var s := IncidentSubject.new()
	s.kind = "lot"
	s.id = n
	s.lot_key = "town:%d" % n
	return s

## Accepts a Folk, a townie id that Story knows, or an existing subject.
static func make(x) -> IncidentSubject:
	if x is IncidentSubject:
		return x
	if x is int:
		var f = SysUtil.folk(int(x))
		return of_folk(f) if f != null else of_townie(int(x))
	return of_folk(x)

func is_full() -> bool:
	return folk != null or lot_key.begins_with("home:")

func t() -> Dictionary:
	return Story.townies.get(id, {}) if kind == "townie" else {}

func display_name() -> String:
	if folk != null:
		return str(folk.name)
	if kind == "townie":
		return str(t().get("name", "Someone"))
	return house_name()

## "The Ashby house" (family name of the first member) or "Your home".
func house_name() -> String:
	if lot_key.begins_with("home:"):
		return "Your home"
	var mem: Array = members()
	if mem.is_empty():
		return "An empty house"
	var parts: PackedStringArray = str(mem[0].display_name()).split(" ")
	return "The %s house" % parts[parts.size() - 1]

func age_stage() -> String:
	if folk != null:
		return str(folk.age_stage)
	return Story.stage_of(t()) if kind == "townie" else "adult"

func has_trait(tr: String) -> bool:
	if folk != null:
		return folk.has_trait(tr)
	return (t().get("traits", []) as Array).has(tr)

func skill_level(sk: String) -> int:
	if folk != null:
		return folk.skill_level(sk)
	var rec: Dictionary = t()
	var own: Dictionary = rec.get("skills", {})
	if own.has(sk):
		return int(own[sk])
	if CAREER_SKILL.get(str(rec.get("career", "")), "") == sk:
		return int(rec.get("level", 1)) + 1
	return 0

func has_buff(b: String) -> bool:
	if folk != null:
		return folk.has_buff(b)
	return (t().get("buffs", []) as Array).has(b)

func stat(sname: String) -> float:
	if folk != null:
		return folk.get_stat_value(sname)
	return float((t().get("needs", {}) as Dictionary).get(sname, 0.0))

func coins() -> int:
	if folk != null:
		return WorldIface.get_coins(household_id)
	return int(t().get("coins", 0))

## During an hourly / daily check run (IncidentChecks.run) the answers below are cached: nothing changes between two dice of the same pass until a hit
## (IncidentChecks clears the cache then). Outside a run nothing is cached.
static var caching := false
static var _members: Dictionary = {}       # town lot number -> member subjects
static var _on_map_ids: Dictionary = {}    # townie id -> true for townies standing on the map as Folk
static var _on_map_ok := false

static var _have: Dictionary = {}          # household id -> def ids of the objects it owns (Economy.objects_of scans every object in the world)

static func household_defs(hid: int) -> Array:
	if not _have.has(hid):
		var out: Array = []
		for o in Economy.objects_of(hid):
			out.append(str(o.def_id))
		_have[hid] = out
	return _have[hid]

static func clear_cache() -> void:
	_have.clear()
	_members.clear()
	_on_map_ids.clear()
	_on_map_ok = false

## Members of a lot subject (subjects); a folk / townie answers with itself.
func members() -> Array:
	var out: Array = []
	if kind == "folk" or kind == "townie":
		return [self]
	if lot_key.begins_with("home:"):
		for f in SysUtil.residents():
			if int(f.household_id) == household_id:
				out.append(of_folk(f))
	else:
		var n: int = int(lot_key.get_slice(":", 1))
		if caching and _members.has(n):
			return _members[n]
		var ids: Array = Story.townies.keys()
		ids.sort()
		for tid in ids:
			var rec: Dictionary = Story.townies[tid]
			if bool(rec["alive"]) and int(rec.get("lot", 0)) == n and not on_map(int(tid)):
				out.append(of_townie(int(tid)))
		if caching:
			_members[n] = out
	return out

func head():
	var m: Array = members()
	return m[0] if not m.is_empty() else null

## The player's own households and anyone one of their folk has met are "known" (toast-worthy).
func known_by_household() -> bool:
	if household_id > 0 or lot_key.begins_with("home:"):
		return true
	var ids: Array = [id] if kind == "townie" else []
	if kind == "lot":
		for m in members():
			ids.append(m.id)
	for r in SysUtil.residents():
		for i in ids:
			if RelationshipService.knows(int(r.id), int(i)):
				return true
	return false

## Is this townie standing on the map as a (visitor) Folk? Then the FULL version handles them.
static func on_map(townie_id: int) -> bool:
	if caching:
		if not _on_map_ok:
			_on_map_ids.clear()
			for g in WorldIface.all_folk():
				if g.has_meta("townie_id"):
					_on_map_ids[int(g.get_meta("townie_id"))] = true
			_on_map_ok = true
		return _on_map_ids.has(townie_id)
	for f in WorldIface.all_folk():
		if f.has_meta("townie_id") and int(f.get_meta("townie_id")) == townie_id:
			return true
	return false

## Real Folk standing on the map for this townie, or null.
static func map_folk(townie_id: int):
	for f in WorldIface.all_folk():
		if f.has_meta("townie_id") and int(f.get_meta("townie_id")) == townie_id:
			return f
	return null
