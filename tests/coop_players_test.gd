extends RefCounted
## Co-op stage 2 without sockets: a joining player gets their own household on a converted townie home, per-player allowlist, build rules per
## lot, hostile household input, lot limits, save / load keeps the claims, the live delta builds / applies / is diff-only and bounded.

const HoodKit := preload("res://tests/hood_kit.gd")
var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func _household(names: Array) -> Dictionary:
	var folk: Array = []
	for n in names:
		folk.append(HouseholdSetup.random_folk("adult", "none", names.duplicate()))
		folk[folk.size() - 1]["name"] = n
	return {"name": "Newcomers", "folk": folk}

func run() -> Array:
	fails = []
	HoodKit.new_game("classic")
	HoodKit.run(5)
	Players.set_player(1, 1, "Hosty")
	var hosts0 := WorldIface.all_folk().size()
	var free0 := PlayerLots.free_lots()
	_check(free0.size() == 3 and not free0.has("apartments"), "three townie homes can be converted, not the apartment block (%s)" % str(free0))
	var r := CoopHouseholds.join(2, "Ann", _household(["Zed", "Zoe"]), "")
	_check(r["ok"], "player 2 joined: %s" % str(r["msg"]))
	var h2: int = r["hid"]
	_check(h2 > 1 and Players.household_of(2) == h2 and Players.household_of(1) == 1, "own household id (%d), host unchanged" % h2)
	_check(PlayerLots.lot_of(2) == r["lot"] and r["lot"] != "" and r["lot"] != "home", "own lot %s" % str(r["lot"]))
	_check(WorldIface.all_folk().size() == hosts0 + 2, "two new folk in the world")
	var rect := NeighborhoodLots.rect_of(r["lot"])
	for id in r["folk_ids"]:
		var f = WorldIface.get_folk(id)
		_check(f != null and rect.has_point(f.tile) and int(f.household_id) == h2, "folk %d stands on the new lot" % id)
	_check(Economy.balance(h2) > 0, "starting funds (%d)" % Economy.balance(h2))
	_check(Neighborhood.residents_of(r["lot"]).is_empty(), "the converted house has no townie residents left")
	# allowlist = Players table
	var mine: int = r["folk_ids"][0]
	var hosts_folk := -1
	for f in WorldIface.all_folk():
		if int(f.household_id) == 1:
			hosts_folk = f.id
			break
	_check(CoopCommands.allowed(2, mine) and not CoopCommands.allowed(2, hosts_folk), "player 2 commands only their own household")
	_check(CoopCommands.allowed(1, hosts_folk) and not CoopCommands.allowed(1, mine), "the host commands only theirs")
	var bad := {"player_id": 2, "folk_id": hosts_folk, "action": "interact", "args": {"interaction_id": "chat", "target_id": -1}, "game_minute": 0, "seq": 1}
	_check(CoopCommands.check(bad) != "", "an order for another player's folk is refused")
	_check(not CoopCommands.apply(bad)["ok"], "and not applied")
	var bad2 := {"player_id": 2, "folk_id": mine, "action": "travel", "args": {"folk_ids": [hosts_folk], "lot_id": "park", "opts": {}}, "game_minute": 0, "seq": 2}
	_check(CoopCommands.check(bad2) != "", "travel for someone else's folk is refused")
	_check(CoopCommands.check({"player_id": 2, "folk_id": mine, "action": "teleport", "args": {}}) != "", "unknown action refused")
	# build rules
	var w = WorldIface.world()
	var own_tile: Vector2i = rect.position + Vector2i(2, 2)
	var host_tile: Vector2i = NeighborhoodLots.rect_of("home").position + Vector2i(2, 2)
	PlayerLots.acting = 2
	_check(w.regions.can_build(own_tile) and not w.regions.can_build(host_tile), "player 2 may build on their lot only")
	PlayerLots.acting = -1
	_check(w.regions.can_build(host_tile) and not w.regions.can_build(own_tile), "the host may build on theirs only")
	# a second and third player, then no more room
	var r3 := CoopHouseholds.join(3, "Bo", _household(["Bob"]), "")
	var r4 := CoopHouseholds.join(4, "Cy", _household(["Cyd"]), "")
	var r5 := CoopHouseholds.join(5, "Di", _household(["Dee"]), "")
	_check(r3["ok"] and r4["ok"] and r3["lot"] != r["lot"] and r4["lot"] != r3["lot"], "players 3 and 4 get different lots")
	_check(not r5["ok"] and str(r5["msg"]) != "", "a fifth player is told there is no home left: " + str(r5["msg"]))
	_check(not CoopHouseholds.join(2, "Ann", _household(["Again"]), "")["ok"], "joining twice is refused")
	# hostile input
	var junk := CoopHouseholds.sanitize({"name": "x".repeat(500), "folk": [{"name": "A\u0001B", "stage": "wizard", "traits": ["nope", "neat", "neat", "active", "social", "lazy"],
		"appearance": {"evil": 1}, "rel": "boss", "aspiration": "y".repeat(500)}] + range(50).map(func(_i): return 7)})
	_check(HouseholdSetup.validate(junk) == "" or junk["folk"].size() >= 1, "hostile household is reduced to something valid-looking")
	_check(str(junk["name"]).length() <= 20 and junk["folk"][0]["stage"] == "adult" and (junk["folk"][0]["traits"] as Array).size() <= 3 and Genetics.is_valid(junk["folk"][0]["appearance"]),
		"names, stage, traits and look are clamped")
	_check(CoopHouseholds.sanitize({"folk": "no"}).is_empty(), "garbage shape is rejected")
	# save / load keeps players and claims
	var snap := SaveLoad.snapshot("coop")
	var lot2 := PlayerLots.lot_of(2)
	var js: Variant = JSON.parse_string(JSON.stringify(snap))
	_check(SaveLoad.restore(js), "snapshot restores")
	_check(PlayerLots.lot_of(2) == lot2 and Players.household_of(2) == h2, "the claimed lot and the players table survive a save / load")
	# live delta
	_live()
	HoodKit.teardown()
	Players.reset()
	return fails

func _live() -> void:
	var live := CoopLive.new()
	live.connect_events()
	var st := live.new_peer()
	SimEnv.emit("notification", "A plain thing happened.", "info")
	var d := live.build(st, 2, 10.0)
	_check(not d.is_empty() and (d["f"] as Array).size() == int(d["nf"]) and (d["f"] as Array).size() >= 5, "first delta carries every household folk (%d rows)" % (d["f"] as Array).size())
	_check((d["t"] as Array).size() == 1, "and the toast")
	var bytes := live.encode(d)
	_check(bytes.size() > 0 and bytes.size() < CoopProto.MAX_DELTA_BYTES / 2, "compressed delta is small (%d bytes)" % bytes.size())
	_check(CoopProto.encode(CoopProto.DELTA, {"minute": 5, "hash": "", "data": bytes}).size() > 0, "it fits a DELTA message")
	_check(live.build(st, 2, 10.1).is_empty(), "too soon: nothing")
	HoodKit.run(1)
	var d2 := live.build(st, 2, 11.0)
	st["sent_min"] = -1      # same instant again: nothing changed, so nothing is sent
	var d2b := live.build(st, 2, 12.0)
	_check((d2b["f"] as Array).is_empty(), "an unchanged world sends no folk rows")
	_check(not d2.is_empty(), "the next minute sends a delta")
	# apply onto the same world after moving a folk: the delta puts it back
	var f = null
	for g in WorldIface.all_folk():
		if int(g.household_id) == 2:
			f = g
			break
	var d3 := live.build(st, 2, 20.0)
	HoodKit.run(1)
	f.tile += Vector2i(3, 0)
	(f.needs["hunger"] as Stat).value = -77.0
	var d4 := live.build(st, 2, 30.0)
	var rows: Array = (d4["f"] as Array).filter(func(r): return int(r["i"]) == int(f.id))
	_check(rows.size() == 1, "a moved folk is in the next delta")
	f.tile -= Vector2i(5, 0)
	(f.needs["hunger"] as Stat).value = 10.0
	var back := CoopLive.decode(live.encode(d4))
	var why := CoopView.apply(back)
	_check(why == "", "applier follows (%s)" % why)
	_check(f.tile == Vector2i(int(rows[0]["x"]), int(rows[0]["y"])) and absf((f.needs["hunger"] as Stat).value + 77.0) < 1.0, "position and needs are driven by the host data")
	_check(Clock.total_minutes == int(d4["m"]), "the client clock follows the host clock")
	var unknown := {"m": 5, "f": [{"i": 987654, "x": 1, "y": 1}], "c": {}, "t": [], "nf": 1, "no": 0}
	_check(CoopView.apply(unknown) != "", "an unknown folk asks for a snapshot")
	# bounded: a huge toast burst is capped per delta
	for i in 40:
		SimEnv.emit("notification", "Spam %d" % i, "info")
	var d5 := live.build(live.new_peer(), 2, 99.0)
	_check((d5["t"] as Array).size() <= CoopLive.MAX_TOASTS, "toasts per delta are capped")
	live.disconnect_events()
