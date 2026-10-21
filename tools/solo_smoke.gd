extends SceneTree
## "It runs" check of one-character play (not a test suite): boot, start a new solo game through the real NewGame path, play one in-game day
## (the pawn is ordered to do a few things), print a few facts. Any script error in the output is the failure.
##   Godot --headless --path . --script res://tools/solo_smoke.gd [-- days]
const Kit := preload("res://tests/start_kit.gd")
var _done := false

func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	var days := 1
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			days = int(a)
	var folk: Array = Kit.new_game("solo", "normal", {}, -1, {"world_seed": 4242, "home_state": "empty"})
	var f: Folk = folk[0]
	var verbose := "--toasts" in OS.get_cmdline_user_args()
	if verbose:
		SimEnv.events().notification.connect(func(text, kind): print("  [d%d %02d:00 %s] %s" % [Kit.clock().day(), Kit.clock().hour(), kind, text]))
	var hs := {}
	for t in Story.alive_townies():
		hs[str(t.get("heritage", ""))] = int(hs.get(str(t.get("heritage", "")), 0)) + 1
	print("SMOKE heritage: pawn=%s townies=%s" % [f.heritage, str(hs)])
	print("SMOKE start: folk=%d pawn=%s coins=%d rung=%s homeless=%s day=%d hour=%d" % [folk.size(), str(Pawn.is_pawn(f)), Economy.balance(f.household_id), SoloHome.rung, str(SoloHome.homeless), Kit.clock().day(), Kit.clock().hour()])
	if "--npc" in OS.get_cmdline_user_args():
		Players.table.clear()          # the reviewer's probe: nobody plays, the household lives on NPC autonomy
		Economy.spend(f.household_id, Economy.balance(f.household_id), "smoke: broke")
		SimEnv.events().notification.connect(func(text, kind): if "ent" in text or "EVICT" in text: print("  [d%d] %s" % [Kit.clock().day(), text]))
		for h in 24 * 32:
			Kit.run(60)
		print("SMOKE npc: homeless=%s rung=%s coins=%d" % [str(SoloHome.homeless), SoloHome.rung, Economy.balance(f.household_id)])
		Kit.teardown()
		quit(0)
		return true
	if "--prompts" in OS.get_cmdline_user_args():
		JusticePlayer.ask_fn = func(_pid, title, text, options, on_choice, default_id):
			print("PROMPT [%s] %s" % [title, text])
			for o in options:
				print("    - %s" % str(o["label"]))
			on_choice.call(default_id)
		var t0: Dictionary = Story.alive_townies().filter(func(x): return Story.stage_of(x) == "adult")[0]
		var tid: int = int(t0["id"])
		t0["coins"] = 0
		t0["career"] = ""
		for round in 2:
			PlayerRequests.romance_step(f.id, tid, "sweetheart")
			PlayerRequests.party(tid, f.id, 1)
			PlayerPrompt.asked.clear()
			PlayerPrompt.ask("loan", f.id, tid, {"amount": 30}, func(_c): pass)
			PlayerPrompt.asked.clear()
		Kit.teardown()
		quit(0)
		return true
	if "--react" in OS.get_cmdline_user_args():
		var t0: Dictionary = Story.alive_townies().filter(func(x): return Story.stage_of(x) == "adult")[0]
		var other: Folk = Crowd.spawn_npc(t0, "market", "market")
		var tally := {}
		for iid in ["kiss", "flirt", "share_secret", "insult", "prank", "hug"]:
			tally.clear()
			for i in 60:
				other.set_meta("x", i)
				var d: Dictionary = SimEnv.data().interaction_def(iid)
				var res: Dictionary = SocialDynamics.resolve(f.id, other.id, iid, d)
				var k: String = str(res.get("reaction", res.get("tier", "?")))
				tally[k] = int(tally.get(k, 0)) + 1
			print("REACT %-12s gap=%.2f runnable=%s %s" % [iid, SocialFit.gap(f.id, other.id, SimEnv.data().interaction_def(iid)), str(Interaction.def_runnable(SimEnv.data().interaction_def(iid), f, null, other)), str(tally)])
		Kit.teardown()
		quit(0)
		return true
	if "--door" in OS.get_cmdline_user_args():
		var hl: String = ""
		for l in Neighborhood.lots():
			if str(l.get("type", "")) == "townie_home":
				hl = str(l["id"])
				break
		var seen := []
		SimEnv.events().game_event.connect(func(n, p): if n == "doorstep": seen.append(str(p)))
		SimEnv.events().notification.connect(func(text, kind): print("  TOAST %s" % text))
		print("DOOR travel to %s: %s" % [hl, str(Neighborhood.travel([f.id], hl, {}))])
		for m in 40:
			Kit.run(10)
			if not seen.is_empty():
				break
		print("DOOR doorstep events=%s at_door=%s tile=%s lot_at=%s" % [str(seen), str(f.get_meta("at_door", "")), str(f.tile), NeighborhoodLots.lot_at(f.tile)])
		var ents: Array = DoorActs.entries(f, hl)
		print("DOOR options=%s" % str(ents.map(func(e): return e["label"])))
		DoorActs.knock(f, hl)
		DoorActs.try_door(f, hl)
		print("DOOR after try: options=%s" % str(DoorActs.entries(f, hl).map(func(e): return e["label"])))
		DoorActs.pick(f, hl)
		DoorActs.force(f, hl)
		print("DOOR inside=%s lot=%s" % [str(DoorActs.intruders), Neighborhood.lot_of(f)])
		for m2 in 12:
			Kit.run(1)
			for pm in JusticeState.pending.duplicate():
				if SysUtil.now() >= int(pm["due_min"]):
					JusticeState.pending.erase(pm)
					CrimeFlow.run_pending(pm)
		Kit.teardown()
		quit(0)
		return true
	if "--ledger" in OS.get_cmdline_user_args():
		Economy.deposit(f.household_id, 100, "smoke")
		Commands.run({"player_id": 1, "folk_id": f.id, "action": "solo", "args": {"action": "move", "rung": "bedsit"}})
		ChronicleHook.note("burglary", "Someone broke into the bedsit.", [f.id], "home:%d" % f.household_id, 3, true)
		Kit.run(60 * 24 * 3)
		ChronicleHook.note("eviction", "The landlord kept the deposit.", [f.id], "home:%d" % f.household_id, 3, true)
		var b: Dictionary = LifeSummary.build(f.id, str(f.name))
		for s in b["sections"]:
			print("SMOKE ledger section %s: %s" % [s["title"], str(s["lines"])])
		Kit.teardown()
		quit(0)
		return true
	if "--walk" in OS.get_cmdline_user_args():
		print("SMOKE travel: %s" % str(Neighborhood.travel([f.id], "cafe")))
		for i in 6:
			Kit.run(10)
			print("SMOKE walk +%d min: tile=%s current=%s queue=%d lot=%s" % [(i + 1) * 10, str(f.tile), str(f.current.def_id) if f.current != null else "-", f.queue.size(), Neighborhood.lot_of(f)])
		Kit.teardown()
		quit(0)
		return true
	if "--rough" in OS.get_cmdline_user_args():
		_rough(f, Kit)
		Kit.teardown()
		quit(0)
		return true
	if "--ladder" in OS.get_cmdline_user_args():
		_ladder(f, Kit)
		Kit.teardown()
		quit(0)
		return true
	for h in 24 * days:
		Kit.run(60)
	if "--bills" in OS.get_cmdline_user_args():
		for b in Economy.bills:
			print("SMOKE bill id=%s reason=%s amount=%s issued=%s due=%s paid=%s late=%s" % [str(b.get("id")), str(b.get("reason", "util")), str(b.get("amount")), str(b.get("issued")), str(b.get("due")), str(b.get("paid")), str(b.get("late"))])
		var pp: Dictionary = SoloHome.prop()
		print("SMOKE prop: %s" % str(pp))
	print("SMOKE housing: rung=%s homeless=%s lot_here=%s shelter_nights=%d" % [SoloHome.rung, str(SoloHome.homeless), Neighborhood.lot_of(f), SoloHome.shelter_nights])
	print("SMOKE end: alive=%s coins=%d hunger=%.0f energy=%.0f day=%d current=%s bills=%d" % [str(SysUtil.folk(f.id) != null), Economy.balance(f.household_id), f.get_stat_value("hunger"), f.get_stat_value("energy"), Kit.clock().day(), str(f.current.def_id) if f.current != null else "-", Economy.outstanding(f.household_id).size()])
	Kit.teardown()
	quit(0)
	return true

## Targeted check of the housing code: buy something, move to the bedsit and back, give the flat up, play two days on the street.
func _ladder(f: Folk, Kit) -> void:
	Economy.deposit(f.household_id, 600, "smoke money")
	var sofa: int = WorldIface.world().place_object("sofa_bed", NeighborhoodLots.entry_tile("home") + Vector2i(-3, -3), 0)
	print("SMOKE sofa placed id=%d" % sofa)
	if sofa >= 0:
		Economy.owner[sofa] = f.household_id
	for step in ["bedsit", "starter", "better"]:
		var r: Dictionary = Commands.run({"player_id": 1, "folk_id": f.id, "action": "solo", "args": {"action": "move", "rung": step}})
		print("SMOKE move %s -> %s | home lot=%s phys=%s pawn at lot=%s tile=%s coins=%d" % [step, str(r), Neighborhood.label_of("home"), str(SoloHome.phys), Neighborhood.lot_of(f), str(f.tile), Economy.balance(f.household_id)])
		Kit.run(60 * 30)
		print("SMOKE after 30h: alive=%s lot=%s hunger=%.0f rung=%s" % [str(SysUtil.folk(f.id) != null), Neighborhood.lot_of(f), f.get_stat_value("hunger"), SoloHome.rung])
	var g: Dictionary = Commands.run({"player_id": 1, "folk_id": f.id, "action": "solo", "args": {"action": "give_up_home"}})
	print("SMOKE give up -> %s | lot=%s tile=%s homeless=%s" % [str(g), Neighborhood.lot_of(f), str(f.tile), str(SoloHome.homeless)])
	var t: Dictionary = Neighborhood.travel([f.id], "home")
	print("SMOKE travel home while homeless -> %s" % str(t.get("reason", "")))
	var sh: Dictionary = Neighborhood.travel([f.id], "shelter", {"instant": true})
	print("SMOKE travel to shelter -> ok=%s lot=%s" % [str(sh.get("ok")), Neighborhood.lot_of(f)])
	Kit.run(60 * 24)
	var sr: Dictionary = Commands.run({"player_id": 1, "folk_id": f.id, "action": "interact", "args": {"interaction_id": "sleep_rough", "target_id": -1}})
	print("SMOKE sleep_rough order -> %s current=%s" % [str(sr), str(f.current.def_id) if f.current != null else "-"])
	Kit.run(60 * 24)
	print("SMOKE end ladder: alive=%s coins=%d day=%d rough_nights=%d" % [str(SysUtil.folk(f.id) != null), Economy.balance(f.household_id), Kit.clock().day(), SoloHome.rough_nights])

## Targeted check of the Kiln Quarter: move to the bedsit, run broke, answer the crew offers "yes", force a drive-by, play a week.
func _rough(f: Folk, Kit) -> void:
	Economy.deposit(f.household_id, 300, "smoke money")
	var r: Dictionary = Commands.run({"player_id": 1, "folk_id": f.id, "action": "solo", "args": {"action": "move", "rung": "bedsit"}})
	print("SMOKE move bedsit -> %s district=%s roughness=%.2f" % [str(r.get("ok")), SoloDistricts.district_of("home"), SoloDistricts.roughness_of("kiln")])
	Economy.spend(f.household_id, maxi(Economy.balance(f.household_id) - 40, 0), "smoke spend")
	JusticePlayer.auto = "yes"
	for d in 8:
		if d == 3:
			SoloCrews.due_abs = (Kit.clock().day() - 1) * 24 + Kit.clock().hour() + 2
			SoloCrews.district_id = "kiln"
			print("SMOKE forcing a drive-by at abs hour %d" % SoloCrews.due_abs)
		Kit.run(60 * 24)
		print("SMOKE day %d: coins=%d member=%s heat=%.0f refusals=%d records=%d burglary_mult=%.1f robbery_mult=%.1f" % [Kit.clock().day(), Economy.balance(f.household_id), str(SoloPressure.member), SoloPressure.heat, SoloPressure.refusals, (JusticeState.records.get(f.id, []) as Array).size(), SoloDistricts.mult("home", "burglary"), SoloDistricts.mult("home", "robbery")])
