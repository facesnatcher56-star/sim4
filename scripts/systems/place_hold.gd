class_name PlaceHold
extends RefCounted
## Task 46: being held at a real place. A person in custody is in a cell of the police station (map lot "police", level -1), on the map, on a bunk, for the whole
## hold: an Away record flagged visible (Away.begin_visible) so the justice code (Away.is_away / info, JusticePlayer.release, care meals) works as before. While held
## the player's orders for that person are refused (Commands.run); at the end of the hold (the time is up, or JusticePlayer.release) they walk out of the door.
## Reasons and lots: data/justice.json "places" ({reason: lot id}). A reason with no lot (or no map: classic stub tests) stays the hidden Away hold.
##   PlaceHold.available(reason)   PlaceHold.begin(f, minutes, reason, label)   PlaceHold.holding(fid)   PlaceHold.end(f)   PlaceHold.on_minute()

const LEVEL := -1
const BUNK := "cell_bunk"

static func lot_of_reason(reason: String) -> String:
	return str((JusticeState.sect("places") as Dictionary).get(reason, ""))

static func available(reason: String) -> bool:
	var lot: String = lot_of_reason(reason)
	if lot == "":
		return false
	var w = WorldIface.world()
	return w != null and "regions" in w and w.regions.has_regions() and NeighborhoodLots.rect_of(lot).size != Vector2i.ZERO

static func holding(fid: int) -> bool:
	return Away.is_visible(fid) and bool((Away.info(fid).get("data", {}) as Dictionary).get("place_hold", false))

## A free bunk of the lot (level LEVEL), the first one nobody was put on; any bunk when all are taken.
static func _bunk(lot: String, fid: int):
	var rc: Rect2i = NeighborhoodLots.rect_of(lot)
	var taken: Dictionary = {}
	for f in SysUtil.residents():
		if int(f.id) != fid and f.has_meta("cell"):
			taken[int(f.get_meta("cell"))] = true
	var free: Array = []
	var all: Array = []
	for o in WorldIface.objects_near(rc.get_center(), 80):
		if rc.has_point(o.tile) and int(o.level if "level" in o else 0) == LEVEL and (str(o.def_id) if "def_id" in o else str(o.def)) == BUNK:
			all.append(o)
			if not taken.has(int(o.id)):
				free.append(o)
	var pool: Array = free if not free.is_empty() else all
	pool.sort_custom(func(a, b): return a.id < b.id)
	return null if pool.is_empty() else pool[0]

static func begin(f, minutes: float, reason: String, label: String) -> bool:
	var lot: String = lot_of_reason(reason)
	var fid: int = int(f.id)
	var bunk = _bunk(lot, fid)
	if bunk == null:
		return false
	var r: Dictionary = Neighborhood.travel([fid], lot, {"instant": true, "free": true, "silent": true, "quiet": true})
	if not bool(r.get("ok", false)):
		return false
	f.set_meta("cell", int(bunk.id))
	var go: Interaction = Interaction.create_goto(f, WorldIface.use_tile(bunk, 0), true, LEVEL)
	if go != null:
		f.enqueue(go)
	var sit: Interaction = Interaction.create("sit_chair", f, int(bunk.id), true)
	if sit != null:
		sit.def = sit.def.duplicate(true)
		sit.def["duration_min"] = minutes
		sit.def["per_min"] = {}
		sit.def["cooldown_min"] = 0
		f.enqueue(sit)
	return Away.begin_visible(f, minutes, reason, {"label": label, "place_hold": true, "lot": lot})

## The hold is over: out of the cell, to the door.
static func end(f) -> void:
	var fid: int = int(f.id)
	var rec: Dictionary = Away.end_visible(fid, true)
	if rec.is_empty():
		return
	var lot: String = str((rec.get("data", {}) as Dictionary).get("lot", ""))
	f.remove_meta("cell")
	f.clear_queue()
	f.cancel_current("released")
	if lot != "":
		var out: Interaction = Interaction.create_goto(f, NeighborhoodLots.entry_tile(lot), true, 0)
		if out != null:
			f.enqueue(out)
	SysUtil.game_event("returned_to_lot", {"folk_id": fid, "reason": str(rec.get("reason", "")), "completed": true})

## The hold's time is up (a release by the justice code calls end() itself through Away.recall).
static func on_minute() -> void:
	for fid in Away.active.keys():
		if holding(int(fid)) and SysUtil.now() >= int(Away.active[fid].get("until_min", 0)):
			var f = SysUtil.folk(int(fid))
			if f != null:
				end(f)
