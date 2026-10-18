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
	_check(mins >= 15 and mins <= 90, "walking time from path length is plausible (%d min)" % mins)
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
	WorldIface.coins[1] = 0                            # spent the money on the way
	Kit.run(int(r2["minutes"]) + 12)
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
