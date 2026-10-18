class_name SaveLoad
extends RefCounted
## Versioned save files: user://saves/slot<N>.json. Contains the clock, World.save_dict() (when a real World exists),
## every Folk (to_dict) and the state of all systems. Slot 0 is the daily autosave.
## NOTE: ui/save_slots.gd writes the same file names with a different (v1) layout; this loader migrates v1 files.

const DIR := "user://saves"
const FORMAT := "sim4"
const VERSION := 2

static var last_error: String = ""
static var autosave_slot: int = 0

static func path(slot: int) -> String:
	return "%s/slot%d.json" % [DIR, slot]

static func has_slot(slot: int) -> bool:
	return FileAccess.file_exists(path(slot))

static func delete_slot(slot: int) -> void:
	if has_slot(slot):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path(slot)))

## Build the full save dictionary (also used by tests to compare states).
static func snapshot(label: String = "") -> Dictionary:
	var folk: Array = []
	for f in WorldIface.all_folk():
		var fd: Dictionary = f.to_dict()
		fd["extra"] = {"visitor": f.has_meta("visitor"), "townie_id": int(f.get_meta("townie_id", -1)), "away": str(f.get_meta("away", ""))}
		folk.append(fd)
	var world_d: Dictionary = {}
	var w = WorldIface.world()
	if w != null and w.has_method("save_dict"):
		world_d = w.save_dict(false)
	return {
		"format": FORMAT, "version": VERSION, "label": label, "day": SysUtil.day(), "clock_total": SimEnv.now_min(),
		"next_folk_id": Folk._next_id,
		"world": world_d, "folk": folk,
		"systems": {
			"economy": Economy.to_dict(), "careers": Careers.to_dict(), "relationships": RelationshipService.to_dict(),
			"goals": Goals.to_dict(), "aging": Aging.to_dict(), "story": Story.to_dict(), "away": Away.to_dict(),
			"family": Family.to_dict(), "babycare": BabyCare.to_dict(), "weather": Weather.to_dict(),
			"neighborhood": Neighborhood.to_dict(),
		},
	}

static func save(slot: int, label: String = "") -> bool:
	last_error = ""
	DirAccess.make_dir_recursive_absolute(DIR)
	var fa := FileAccess.open(path(slot), FileAccess.WRITE)
	if fa == null:
		last_error = "cannot open %s for writing" % path(slot)
		return false
	fa.store_string(JSON.stringify(snapshot(label)))
	fa.close()
	return true

static func read(slot: int) -> Dictionary:
	var fa := FileAccess.open(path(slot), FileAccess.READ)
	if fa == null:
		return {}
	var js := JSON.new()
	if js.parse(fa.get_as_text()) != OK:
		return {}
	if js.data is Dictionary:
		return js.data
	return {}

static func summary(slot: int) -> String:
	var d: Dictionary = read(slot)
	if d.is_empty():
		return "Empty"
	return "%s - Day %d" % [str(d.get("label", d.get("household_name", "Household"))), int(d.get("day", 1))]

## Upgrade older layouts in place. v1 (ui/save_slots.gd) had no "systems" block.
static func migrate(d: Dictionary) -> Dictionary:
	var v: int = int(d.get("version", 1))
	if v < 2:
		if not d.has("systems"):
			d["systems"] = {}
		d["format"] = FORMAT
		if not d.has("clock_total") and d.has("clock"):
			d["clock_total"] = d["clock"]
		d["version"] = 2
	return d

static func load_slot(slot: int) -> bool:
	last_error = ""
	var d: Dictionary = read(slot)
	if d.is_empty():
		last_error = "slot %d is empty or corrupt" % slot
		return false
	return restore(d)

## Same as load_slot(slot).
static func load(slot: int) -> bool:
	return load_slot(slot)

static func restore(d: Dictionary) -> bool:
	d = migrate(d)
	if int(d.get("version", 0)) > VERSION:
		last_error = "save is from a newer version"
		return false
	# clock
	var clk = SimEnv.clock()
	if clk.has_method("reset"):
		clk.call("reset", int(d.get("clock_total", clk.total_minutes)))
	else:
		clk.total_minutes = int(d.get("clock_total", clk.total_minutes))
	# world
	var w = WorldIface.world()
	for f in WorldIface.all_folk().duplicate():
		f.current = null          # break Folk <-> Interaction reference cycles before dropping them
		f.queue.clear()
		SysUtil.world_remove_folk(int(f.id))
	var world_d: Dictionary = d.get("world", {})
	if w != null and w.has_method("load_dict") and not world_d.is_empty():
		w.load_dict(world_d)
		for f2 in WorldIface.all_folk().duplicate():    # we restore folk ourselves
			SysUtil.world_remove_folk(int(f2.id))
	# systems that must exist before folk are placed (so buffs/relationships line up)
	var sy: Dictionary = d.get("systems", {})
	RelationshipService.from_dict(sy.get("relationships", {}))
	Economy.from_dict(sy.get("economy", {}))
	# folk
	var folk_list: Array = d.get("folk", [])
	var keep_next: int = int(d.get("next_folk_id", 0))
	for fd in folk_list:
		var f3 = Folk.from_dict(fd)
		var ex: Dictionary = fd.get("extra", {})
		if bool(ex.get("visitor", false)):
			f3.set_meta("visitor", true)
			f3.set_meta("townie_id", int(ex.get("townie_id", -1)))
		SysUtil.world_add_folk(f3, f3.tile)
	var townie_first: int = int(SysUtil.table("story").get("first_id", 1000))
	for fd2 in folk_list:      # visitors carry townie ids; they must not inflate the id counter
		if int(fd2["id"]) < townie_first:
			keep_next = maxi(keep_next, int(fd2["id"]) + 1)
	Folk._next_id = keep_next if keep_next > 0 else Folk._next_id
	Careers.from_dict(sy.get("careers", {}))
	Goals.from_dict(sy.get("goals", {}))
	Aging.from_dict(sy.get("aging", {}))
	Story.from_dict(sy.get("story", {}))
	Family.from_dict(sy.get("family", {}))
	BabyCare.from_dict(sy.get("babycare", {}))
	for f4 in WorldIface.all_folk():
		RelationshipService.restore_folk(f4)
	Away.from_dict(sy.get("away", {}))
	Weather.from_dict(sy.get("weather", {}))
	SysContent.install()
	FamilyContent.install()
	WeatherContent.install()
	NeighborhoodService.install()
	Neighborhood.from_dict(sy.get("neighborhood", {}))
	return true

## Autosave (slot 0) — SystemsManager calls this each game day.
static func autosave() -> bool:
	return save(autosave_slot, "Autosave")
