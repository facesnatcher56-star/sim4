extends RefCounted
## A folk walks from its home to a venue on the continuous map in game time (real path length -> real minutes), the venue entry
## rules apply when it gets there (fee charged on arrival, closed hours turn it away), fast travel still hides it for a while,
## and a save made in the middle of a walk resumes the walk.

const Kit = preload("res://tests/hood_kit.gd")

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	_walk_to_cafe()
	_fee_on_arrival()
	_closed_hours()
	_fast_travel()
	_save_mid_walk()
	_visitors_walk_in()
	_sidewalk_walk()
	_interrupted_trip()
	_leavers_walk_out()
	Kit.teardown()
	return fails

func _walk_to_cafe() -> void:
	var folk: Array = Kit.new_game("small")
	var mira: Folk = folk[0]
	Kit.set_time(2, 12)
	WorldIface.coins[1] = 500
	var start: Vector2i = mira.tile
	_check(Neighborhood.where(mira.id) == "home", "starts at home (%s)" % Neighborhood.where(mira.id))
	var r: Dictionary = Neighborhood.travel([mira.id], "cafe", {"quiet": true})
	_check(bool(r["ok"]), "walk to the cafe starts: %s" % str(r.get("reason", "")))
	var mins: int = int(r["minutes"])
	print("  [walk] home -> cafe: %d min (path %d tiles)" % [mins, WorldIface.path_length(start, Neighborhood.entry_tile("cafe"))])
	_check(mins >= 8 and mins <= 45, "walking time from path length is plausible (%d min)" % mins)
	_check(not mira.has_meta("away") and Neighborhood.heading_to(mira.id) == "cafe" and Neighborhood.traveling(mira.id), "the folk is walking, not hidden")
	Kit.run(3)
	_check(mira.current != null and mira.current.def_id == "go_here", "walking is a go_here interaction (%s)" % (mira.current.def_id if mira.current != null else "none"))
	_check(mira.tile != start, "the folk left its tile")
	Kit.run(mins / 2)
	_check(Neighborhood.where(mira.id) != "cafe" and Neighborhood.where(mira.id) != "home", "half way: on the street or a lot in between (%s)" % Neighborhood.where(mira.id))
	_check(Neighborhood.where(folk[1].id) == "home", "the others stay home")
	Kit.run(mins / 2 + 12)
	_check(Neighborhood.where(mira.id) == "cafe", "arrived at the cafe (lot %s, tile %s)" % [Neighborhood.where(mira.id), str(mira.tile)])
	_check(Kit.has_note("arrived at"), "arrival announced")
	_check(Neighborhood.heading_to(mira.id) == "" and int(Neighborhood.visits.get("cafe", 0)) == 1, "walk finished, visit counted")
	_check(Economy.balance(1) == 500, "the cafe has no entry fee (%d)" % Economy.balance(1))
	_check(Crowd.count("cafe") >= 1 and Crowd.staff_folk("cafe").size() >= 1, "the cafe has locals and staff (%d / %d)" % [Crowd.count("cafe"), Crowd.staff_folk("cafe").size()])

func _fee_on_arrival() -> void:
	var folk: Array = Kit.new_game("small")
	var mira: Folk = folk[0]
	Kit.set_time(2, 9)
	WorldIface.coins[1] = 500
	var r: Dictionary = Neighborhood.travel([mira.id], "gym", {"quiet": true})
	_check(bool(r["ok"]), "walk to the gym starts")
	_check(Economy.balance(1) == 500, "no fee while walking")
	Kit.run(int(r["minutes"]) + 12)
	_check(Neighborhood.where(mira.id) == "gym", "arrived at the gym")
	_check(Economy.balance(1) == 490, "entry fee charged on arrival (%d)" % Economy.balance(1))
	_check(Economy.ledger_for(1).any(func(row): return str(row["reason"]).begins_with("entry: Ironleaf")), "the ledger shows the gym entry")
	Kit.run(30)
	var entries := 0
	for row in Economy.ledger_for(1):
		if str(row["reason"]).begins_with("entry:"):
			entries += 1
	_check(entries == 1, "the entry fee was paid exactly once (%d entry charges)" % entries)
	# a second folk with no money is turned away at the gate
	var wren: Folk = folk[2]
	WorldIface.coins[1] = 15
	var r2: Dictionary = Neighborhood.travel([wren.id], "gym", {"quiet": true})
	_check(bool(r2["ok"]), "affordable trip starts")
	for _m in int(r2["minutes"]) + 12:                  # spent the money on the way (and stays broke: wages may arrive on a long walk)
		WorldIface.coins[1] = 0
		Kit.run(1)
	_check(Neighborhood.where(wren.id) != "gym" and Kit.has_note("Entry costs"), "no money at the gate: turned away (wren at %s %s heading %s, doing %s, %d min planned)" % [Neighborhood.where(wren.id), str(wren.tile), Neighborhood.heading_to(wren.id), wren.current.def_id if wren.current != null else "-", int(r2["minutes"])] + " denied=%s in_lot=%s coins=%d notes=%s" % [str(wren.get_meta("denied", "")), str(wren.get_meta("in_lot", "?")), Economy.balance(1), str(Kit.notes.slice(-5))])

func _closed_hours() -> void:
	var folk: Array = Kit.new_game("small")
	var mira: Folk = folk[0]
	Kit.set_time(2, 3)
	var r: Dictionary = Neighborhood.travel([mira.id], "cafe", {"quiet": true})
	_check(not bool(r["ok"]) and str(r["reason"]).to_lower().find("closed") >= 0, "closed cafe: no walk at 03:00 (%s)" % str(r.get("reason", "")))
	_check(Neighborhood.heading_to(mira.id) == "", "the folk stays put")
	# open when she leaves, closed when she gets there
	Kit.set_time(2, 21, 55)                            # the gym closes at 22:00
	WorldIface.coins[1] = 500
	var r2: Dictionary = Neighborhood.travel([mira.id], "gym", {"quiet": true})
	_check(bool(r2["ok"]), "gym is still open when she sets out")
	Kit.run(int(r2["minutes"]) + 25)
	_check(Neighborhood.where(mira.id) != "gym", "turned away: the gym had closed (at %s)" % Neighborhood.where(mira.id))
	_check(Kit.has_note("closed"), "toast says it is closed")
	_check(Economy.balance(1) == 500, "no fee for a closed gym")
	Kit.run(20)
	_check(Neighborhood.where(mira.id) != "gym", "and she stays out")

func _fast_travel() -> void:
	var folk: Array = Kit.new_game("small")
	var mira: Folk = folk[0]
	Kit.set_time(2, 12)
	var r: Dictionary = Neighborhood.travel([mira.id], "park", {"fast": true, "quiet": true})
	_check(bool(r["ok"]) and int(r["minutes"]) >= 5, "fast travel works (%s min)" % str(r.get("minutes")))
	_check(mira.has_meta("away") and str(mira.get_meta("away")) == "travel", "hidden while travelling")
	_check(Neighborhood.where(mira.id) == "park", "already at the park door")
	Kit.run(int(r["minutes"]) + 3)
	_check(not mira.has_meta("away") and Neighborhood.where(mira.id) == "park", "arrived")
	var back: Dictionary = Neighborhood.go_home([mira.id], {"fast": true})
	_check(bool(back["ok"]), "fast trip home")
	Kit.run(int(back["minutes"]) + 3)
	_check(Neighborhood.where(mira.id) == "home", "home again")

func _save_mid_walk() -> void:
	var folk: Array = Kit.new_game("small")
	var mira: Folk = folk[0]
	Kit.set_time(2, 12)
	WorldIface.coins[1] = 500
	var r: Dictionary = Neighborhood.travel([mira.id], "market", {"quiet": true})
	_check(bool(r["ok"]), "walk to the market starts")
	Kit.run(int(r["minutes"]) / 2)
	var tile_before: Vector2i = mira.tile
	_check(Neighborhood.heading_to(mira.id) == "market" and Neighborhood.where(mira.id) != "market", "mid walk (at %s)" % str(tile_before))
	var snap: Dictionary = SaveLoad.snapshot("walk")
	var parsed: Variant = JSON.parse_string(JSON.stringify(snap))
	_check(parsed is Dictionary and int((parsed as Dictionary)["version"]) == SaveLoad.VERSION, "snapshot survives JSON")
	var nb: Dictionary = (parsed as Dictionary)["systems"]["neighborhood"]
	_check(not nb.has("stash") and (nb["walks"] as Dictionary).has(str(mira.id)), "neighborhood block has the walk and no stash")
	_check(((parsed as Dictionary)["world"] as Dictionary).has("regions"), "regions are in the world dict")
	Kit.new_game("large")                                # something else in between
	_check(SaveLoad.restore(parsed), "restore works")
	var m2 = SysUtil.folk(mira.id)
	_check(m2 != null and m2.tile == tile_before, "position preserved (%s vs %s)" % [str(m2.tile) if m2 != null else "-", str(tile_before)])
	_check(Neighborhood.heading_to(mira.id) == "market", "still heading to the market after loading")
	_check(Kit.world().regions.has_regions() and Kit.world().width == World.MAP_W, "the big map is back")
	Kit.run(int(r["minutes"]) + 15)
	_check(Neighborhood.where(mira.id) == "market", "the walk resumed and finished (%s)" % Neighborhood.where(mira.id))
	_check(Neighborhood.pantry == 0 and Economy.balance(1) == 500, "no stray charges (%d)" % Economy.balance(1))

## A townie who lives in another lot appears on the road (at most MAX_GUEST_WALK tiles from the door) and walks to the host.
func _visitors_walk_in() -> void:
	var folk: Array = Kit.new_game("small")
	var mira: Folk = folk[0]
	Kit.set_time(2, 10)
	var guest_id := -1
	for t in Neighborhood.residents_of("townie_b"):
		if Story.stage_of(t) in ["adult", "elder"]:
			guest_id = int(t["id"])
			break
	_check(guest_id >= 0, "an adult lives in townie_b")
	if guest_id < 0:
		return
	var door: Vector2i = Neighborhood.entry_tile("home")
	var sit: Dictionary = StoryVisits.schedule_visit([guest_id], mira.id, SimEnv.now_min() + 2, 120, "visit")
	Kit.run(4)
	var g = SysUtil.folk(guest_id)
	_check(g != null and g.has_meta("visitor"), "the guest arrived as a visitor (state %s)" % str(sit["state"]))
	if g == null:
		return
	var steps: int = WorldIface.path_length(g.tile, door)
	_check(steps <= StoryVisits.MAX_GUEST_WALK + 2, "the guest appeared near the door, not inside the house (%d steps)" % steps)
	_check(Neighborhood.lot_at(g.tile) != "home" or steps > 0, "the guest starts outside")
	Kit.run(40)
	_check(Neighborhood.lot_at(g.tile) == "home", "the guest walked into the home lot (%s at %s)" % [Neighborhood.lot_at(g.tile), str(g.tile)])

## The walker follows the sidewalks: every minute it stands on its start lot, the destination lot, a sidewalk or a crosswalk -
## never on asphalt outside a crosswalk or on the lawn of another lot; it counts as inside only at the gate / door.
func _sidewalk_walk() -> void:
	var folk: Array = Kit.new_game("small")
	var mira: Folk = folk[0]
	var W: Node = Kit.world()
	Kit.set_time(2, 12)
	var r: Dictionary = Neighborhood.travel([mira.id], "cafe", {"quiet": true, "free": true})
	_check(bool(r["ok"]), "walk to the cafe starts")
	var home_id: int = W.region_at(mira.tile)
	var cafe_id: int = W.region_at(Neighborhood.entry_tile("cafe"))
	var crossed := false
	var entered_at := Vector2i(-1, -1)
	var bad: Array = []
	for m in int(r["minutes"]) + 12:
		Kit.run(1)
		for t in _tiles_since(mira):
			var rid: int = W.region_at(t)
			var fl: String = W.get_floor(t)
			crossed = crossed or fl == "crosswalk"
			if not (rid == home_id or rid == cafe_id or fl == "sidewalk" or fl == "crosswalk"):
				bad.append("%s (%s, region %d)" % [str(t), fl, rid])
		if entered_at.x < 0 and str(mira.get_meta("in_lot", "")) == "cafe":
			entered_at = mira.tile
	_check(bad.is_empty(), "the walker stays on sidewalks / crosswalks / its own lots; off-route tiles: %s" % str(bad.slice(0, 5)))
	_check(crossed, "the walk crossed a road on a crosswalk")
	_check(entered_at.x >= 0 and NeighborhoodLots.at_door(entered_at, "cafe"), "the cafe entry rule fired at the gate / door (tile %s)" % str(entered_at))
	_check(Neighborhood.where(mira.id) == "cafe", "arrived (%s)" % Neighborhood.where(mira.id))

var _seen: Dictionary = {}
## Tiles the folk's route passed since the last call (the interaction's path up to its current tile).
func _tiles_since(f: Folk) -> Array:
	var out: Array = []
	if f.current != null and f.current.state == "walking":
		var p: Array = f.current.path
		var i: int = p.find(f.tile)
		for k in range(maxi(int(_seen.get(f.id, -1)) + 1, 0), i + 1):
			out.append(p[k])
		_seen[f.id] = i
	else:
		_seen[f.id] = -1
		out.append(f.tile)
	return out

## A walk cut short by something urgent is resumed; one that cannot be resumed in time is dropped with a toast.
func _interrupted_trip() -> void:
	var folk: Array = Kit.new_game("small")
	var mira: Folk = folk[0]
	Kit.set_time(2, 12)
	WorldIface.coins[1] = 500
	var r: Dictionary = Neighborhood.travel([mira.id], "market", {"quiet": true, "free": true})
	_check(bool(r["ok"]), "walk to the market starts")
	Kit.run(4)
	mira.current.cancel("preempted")                          # work shift / emergency took over
	_check(mira.has_meta("resume_walk"), "the cut trip is remembered")
	Kit.run(2)
	_check(NeighborhoodLots.walking_to(mira) == "market", "and re-issued (%s)" % NeighborhoodLots.walking_to(mira))
	Kit.run(int(r["minutes"]) + 12)
	_check(Neighborhood.where(mira.id) == "market", "the interrupted trip still arrived (%s)" % Neighborhood.where(mira.id))
	# a trip that was cut long ago is dropped with a toast instead of being resumed
	var tobin: Folk = folk[1]
	var r2: Dictionary = Neighborhood.travel([tobin.id], "gym", {"quiet": true, "free": true})
	_check(bool(r2["ok"]), "second walk starts")
	Kit.run(2)
	tobin.current.cancel("preempted")
	tobin.set_meta("resume_walk", ["gym", SimEnv.now_min() - NeighborhoodLots.RESUME_MAX_MIN - 5])
	Kit.run(2)
	_check(NeighborhoodLots.walking_to(tobin) == "" and not tobin.has_meta("walk_to"), "a stale cut trip is dropped")
	_check(Kit.has_note("gave up on going to"), "with a toast")

## NPCs leave a venue on foot: one route to the door (a go_here, no per-minute path search), gone once they reach it.
func _leavers_walk_out() -> void:
	var folk: Array = Kit.new_game("small")
	Kit.set_time(2, 12)
	Neighborhood.travel([folk[0].id], "cafe", {"instant": true, "free": true, "quiet": true})
	Kit.run(8)
	var crowd: Array = Crowd.crowd_folk("cafe")
	_check(not crowd.is_empty(), "the cafe has a crowd")
	if crowd.is_empty():
		return
	var npc: Folk = crowd[0]
	var door: Vector2i = Neighborhood.entry_tile("cafe")
	var start: Vector2i = npc.tile
	Crowd._start_leaving(npc)
	_check(npc.has_meta("leaving"), "marked as leaving")
	Kit.run(1)
	var moved := npc.tile != start or start == door
	var seen_walking: bool = npc.current != null and npc.current.def_id == "go_here"
	var left_after := -1
	for m in 14:
		if SysUtil.folk(npc.id) == null:
			left_after = m
			break
		Kit.run(1)
	_check(moved or seen_walking, "the NPC walks towards the door instead of vanishing")
	_check(left_after >= 0 or SysUtil.folk(npc.id) == null, "and is gone within the walk-out time")
