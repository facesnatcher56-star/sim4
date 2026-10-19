class_name CrimePlace
extends RefCounted
## ALL spatial logic of the crime and justice track lives here (so the coming multi-floor world is a one-file change: every position
## will get a level). Other crime files never do raw tile math: they ask where someone was, who can see whom, and where burglars enter.
## Location strings: "home:<hid>" (a household lot), "town:<n>" (a townie lot), "venue:<lot id>", "work", "street", "away", "unknown".

## Floor of a person (0 for ground level and for far townies, who are inside a lot without floors).
static func level_of(pid: int) -> int:
	var f = CrimePerson.folk(pid)
	return int(f.level) if f != null else 0


## Where is this person right now (a location string)? Folk use their tile; far townies follow a simple daily pattern.
## `with_level`: add "#<level>" for a floor other than the ground floor ("home:1#2" = the 2nd floor of the home).
static func where_now(pid: int, with_level: bool = false) -> String:
	var loc := _where_now(pid)
	var lv := level_of(pid)
	return loc if (not with_level or lv == 0) else "%s#%d" % [loc, lv]


static func _where_now(pid: int) -> String:
	var f = CrimePerson.folk(pid)
	if f != null:
		if SysUtil.is_away(f):
			return "work" if str(f.get_meta("away", "")) in ["work", "school"] else "away"
		var lot: String = Neighborhood.lot_of(f)
		if lot == Neighborhood.HOME:
			return "home:%d" % maxi(int(f.household_id), 1) if SysUtil.is_resident(f) else "home:1"
		return "venue:%s" % lot if lot != "" else "street"
	if not Story.townies.has(pid):
		return "unknown"
	var t: Dictionary = Story.townies[pid]
	var h: float = SysUtil.hour_f()
	if h >= 23.0 or h < 6.5:
		return "town:%d" % int(t.get("lot", 0))
	if str(t.get("career", "")) != "" and h >= 9.0 and h < 17.0 and SysUtil.weekday() < 5:
		return "work"
	return "town:%d" % int(t.get("lot", 0)) if (pid + SysUtil.day() + int(h)) % 3 == 0 else "street"

## The recorded whereabouts at an absolute game minute (hourly log), or "unknown". `with_level` keeps the "#<level>" suffix.
static func where_was(pid: int, minute: int, with_level: bool = false) -> String:
	var loc := _where_was(pid, minute)
	return loc if with_level else loc.get_slice("#", 0)


static func _where_was(pid: int, minute: int) -> String:
	var log: Array = JusticeState.whereabouts.get(pid, [])
	if log.is_empty():
		return "unknown"
	var hour_idx: int = minute / 60
	var slot: int = hour_idx % log.size()
	var rec: String = str(log[slot])
	# entries are "<hour index>|<loc>" so a stale slot (older than the ring) is not mistaken for the right hour
	if rec.get_slice("|", 0) != str(hour_idx):
		return "unknown"
	return rec.get_slice("|", 1)

static func log_size() -> int:
	return int(JusticeState.sect("general").get("log_hours", 72))

static func record_now(pid: int, loc: String = "") -> void:
	var log: Array = JusticeState.whereabouts.get(pid, [])
	if log.size() != log_size():
		log.resize(log_size())
		for i in log.size():
			if log[i] == null:
				log[i] = ""
	var hour_idx: int = SysUtil.now() / 60
	log[hour_idx % log.size()] = "%d|%s" % [hour_idx, loc if loc != "" else where_now(pid, true)]
	JusticeState.whereabouts[pid] = log

## Force a person's log entry for the current hour (the culprit really was at the scene).
static func place_at_scene(pid: int, scene: String) -> void:
	record_now(pid, scene)

static func same_place(a: String, b: String) -> bool:
	return a == b and a != "unknown" and a != "street" and a != "away"

## Could `witness` see `subject`? Same lot, within 8 tiles, and on the same floor (nothing in between) or through a stairwell.
static func can_witness(witness_pid: int, subject_pid: int) -> bool:
	var a = CrimePerson.folk(witness_pid)
	var b = CrimePerson.folk(subject_pid)
	if a != null and b != null:
		if Vector2(a.tile - b.tile).length() > 8.0 or Neighborhood.lot_of(a) != Neighborhood.lot_of(b):
			return false
		if int(a.level) == 0 and int(b.level) == 0:
			return true
		var w = WorldIface.world()
		if w == null or not ("levels" in w):
			return int(a.level) == int(b.level)
		return WorldRoomsLevels.can_see(w, Vector3i(a.tile.x, a.tile.y, int(a.level)), Vector3i(b.tile.x, b.tile.y, int(b.level)))
	return where_now(witness_pid) == where_now(subject_pid)

## Residents (player household) who are in the home lot right now and awake: they can notice a break-in.
static func awake_at_home(hid: int) -> Array:
	var out: Array = []
	for f in SysUtil.residents():
		if int(f.household_id) != hid or SysUtil.is_away(f):
			continue
		if Neighborhood.lot_of(f) != Neighborhood.HOME:
			continue
		if is_asleep(f):
			continue
		out.append(f)
	return out

static func is_asleep(f) -> bool:
	return f.current != null and (str(f.current.def_id).begins_with("sleep") or str(f.current.def_id) == "pass_out" or f.posture == "lie")

static func at_home(hid: int) -> Array:
	var out: Array = []
	for f in SysUtil.residents():
		if int(f.household_id) == hid and not SysUtil.is_away(f) and Neighborhood.lot_of(f) == Neighborhood.HOME:
			out.append(f)
	return out

## Where a burglar gets in: the GROUND-floor doors and windows of the lot (tiles; nobody climbs to the 3rd floor window). Falls back to the lot entrance.
static func entry_points(hid: int) -> Array:
	var out: Array = []
	for o in SysUtil.all_world_objects():
		if str(o.def_id) in ["door", "window"] and LevelInfo.lv(o) == 0:
			if Economy.owner.get(int(o.id), hid) == hid:
				out.append(o.tile)
	if out.is_empty():
		out.append(StoryVisits.entrance())
	return out

static func entrance() -> Vector2i:
	return StoryVisits.entrance()

## Tiles an NPC reaches in a few steps: where the burglar stands to take an object.
static func tile_of_object(o) -> Vector2i:
	return o.tile

## Objects of the household that are worth stealing (electronics, art), most valuable first.
static func valuables(hid: int) -> Array:
	var out: Array = []
	for o in Economy.objects_of(hid):
		var def: Dictionary = SimEnv.data().object_def(str(o.def_id))
		var tags: Array = def.get("tags", [])
		if tags.has("electronics") or tags.has("art") or str(o.def_id) in ["easel", "easel_large", "stereo", "computer", "tv", "telescope", "guitar_stand"]:
			out.append(o)
	out.sort_custom(func(a, b): return Economy.value_of(int(a.id)) > Economy.value_of(int(b.id)))
	return out

## Is a light on in the lot (lamps, pendant lights)?
static func lamp_on(hid: int) -> bool:
	for o in Economy.objects_of(hid):
		if str(o.def_id) in ["lamp", "pendant_light"] and bool(WorldIface.state_get(o, "on", false)):
			return true
	return false

## How many tiles apart (for "walked past the place" style checks); floors add to this later.
static func distance(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a - b).length()