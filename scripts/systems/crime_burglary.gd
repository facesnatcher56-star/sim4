class_name CrimeBurglary
extends RefCounted
## Burglary (upgrade of Story's coin-only burglar) and theft by guests. Handlers of incidents `burglary` / `guest_theft` (data/incidents/04_crime.json).
##   HOME LOT (full): a visible townie burglar walks in through a ground-floor door or window at night, takes a valuable object (or coins) and runs.
##     Prevention: burglar alarm (rings, calls the police), a lamp on, someone awake. Residents who are awake (or wake up) can
##     Confront (fitness / brave / hot-headed help) or Call the police. Police arrive after a delay and may catch the burglar and recover the things.
##   TOWNIE LOT (statistical): same dice and the same case record, no walking.
## The scene is a small timed state machine run from CrimeFlow (pending events "burgle_step").

static func cfg() -> Dictionary:
	return JusticeState.sect("burglary")

static func enabled() -> bool:
	return JusticeState.enabled

# ------------------------------------------------------------------ who
## A plausible burglar: poor, jobless, with a record, not honest; never someone from the target house.
static func pick_burglar(lot_key: String, exclude: Array = []) -> int:
	var ids: Array = []
	var w: Array = []
	var k: Dictionary = cfg().get("burglar_weights", {})
	for pid in CrimePerson.sample_townies():
		if exclude.has(pid) or not CrimePerson.is_adult(pid) or CrimePerson.in_custody(pid) or Hospital.is_in(pid):
			continue
		if lot_key == CrimePerson.home_key(pid) or Story.stage_of(CrimePerson.rec(pid)) == "elder":
			continue
		var weight: float = 1.0
		var coins: int = CrimePerson.coins(pid)
		weight *= float(k.get("poor", 3.0)) if coins < 150 else (float(k.get("modest", 1.5)) if coins < 400 else float(k.get("comfortable", 0.4)))
		if not CrimePerson.has_job(pid):
			weight *= float(k.get("jobless", 2.0))
		if CrimePerson.has_record(pid):
			weight *= float(k.get("record", 2.0))
		if CrimePerson.has_trait(pid, "honest"):
			weight *= 0.05
		if CrimePerson.has_trait(pid, "generous") or CrimePerson.has_trait(pid, "forgiving"):
			weight *= 0.4
		if CrimePerson.has_trait(pid, "lazy"):
			weight *= 1.3
		if JusticeState.probation.has(pid):
			weight *= 0.4                      # watched
		weight *= 0.4 + 3.0 * CrimePressure.risk(pid)         # desperate and without a conscience (task 09c)
		if CrimeLifePath.is_member(pid) and CrimeLifePath.rank_index(pid) >= 1:
			weight *= float(CrimeLifeState.sect("townie").get("burglar_weight", 3.0))      # a working burglar (task 21)
		if CrimePerson.has_trait(pid, "dishonest"):
			weight *= 2.0
		ids.append(pid)
		w.append(weight)
	var i: int = JusticeState.pick_index(w)
	return int(ids[i]) if i >= 0 else -1

# ------------------------------------------------------------------ incident handler
static func on_incident(ctx: Dictionary, _args: Dictionary) -> Dictionary:
	if not enabled():
		return {"text": ""}
	return attempt(str(ctx["lot_key"]), bool(ctx["statistical"]), bool(ctx.get("forced", false)))

## One burglary attempt on a lot ("home:1" or "town:3"). Returns {"text", "kind", "case"} (text "" = nothing noticeable happened).
static func attempt(lot_key: String, statistical: bool, forced: bool = false, culprit: int = -1) -> Dictionary:
	if culprit < 0:
		culprit = pick_burglar(lot_key)
	if culprit < 0:
		return {"text": ""}
	var hid: int = int(lot_key.get_slice(":", 1)) if lot_key.begins_with("home:") else 0
	var k: Dictionary = cfg()
	if not forced:
		var abort: String = _prevented(hid, lot_key, statistical)
		if abort != "":
			return {"text": abort, "kind": "good"} if abort != "quiet" else {"text": ""}
	if hid > 0 and not statistical:
		return _start_scene(hid, culprit, forced)
	return _statistical(lot_key, culprit, k)

## Returns "" (go ahead), "quiet" (silently abandoned) or a player-facing text.
static func _prevented(hid: int, lot_key: String, statistical: bool) -> String:
	var k: Dictionary = cfg()
	if hid > 0 and not statistical:
		var awake: Array = CrimePlace.awake_at_home(hid)
		if CrimePlace.lamp_on(hid) and JusticeState.chance(float(k.get("lamp_abort", 0.5))):
			return "quiet"
		if not awake.is_empty() and JusticeState.chance(float(k.get("awake_abort", 0.65))):
			return "A prowler lingered by the window, saw the lights and someone awake, and slipped away."
		for o in Economy.objects_of(hid):
			if str(o.def_id) == "burglar_alarm" and JusticeState.chance(float(k.get("alarm_abort", 0.7))):
				return "quiet"
		var fx: Dictionary = CrimeSecurity.effects(CrimeSecurity.home_profile(hid), true)       # locks, cameras, lights, a dog (task 21)
		if float(fx["abort"]) > 0.0 and CrimeLifeState.chance(float(fx["abort"])):
			return "quiet"
	else:
		if JusticeState.chance(float(k.get("townie_abort", 0.3))):
			return "quiet"
		if lot_key.begins_with("town:") and CrimeLifeState.chance(float(CrimeSecurity.effects(CrimeSecurity.profile_for(lot_key), true)["abort"])):
			return "quiet"
	if CrimeRate.crime_mult() < 1.0 and JusticeState.chance(1.0 - CrimeRate.crime_mult()):
		return "quiet"                          # a safe, well-watched town puts burglars off
	return ""

# ------------------------------------------------------------------ statistical version
static func _statistical(lot_key: String, culprit: int, k: Dictionary) -> Dictionary:
	var owner_pid: int = -1
	var coins: int = 0
	for tid in CrimePerson.townies_only():
		if CrimePerson.home_key(tid) == lot_key:
			owner_pid = tid if owner_pid < 0 else owner_pid
			coins += CrimePerson.coins(tid)
	if owner_pid < 0 and not lot_key.begins_with("home:"):
		return {"text": ""}
	var take: int = clampi(int(float(coins) * float(k.get("coin_share", 0.15))), int(k.get("coin_min", 20)), int(k.get("coin_max", 300)))
	if lot_key.begins_with("town:"):
		take = mini(take, coins)
		if owner_pid >= 0:
			CrimePerson.pay(owner_pid, take, "burglary")
		CrimePerson.add_coins(culprit, take)
	var witnessed: bool = JusticeState.chance(minf(float(k.get("witness_far", 0.2)) * float(CrimeSecurity.effects(CrimeSecurity.profile_for(lot_key), true)["detect"]), 0.9))
	var c: Dictionary = CaseStore.create("burglary", culprit, owner_pid, lot_key, {"witnessed": witnessed, "witnesses": [], "witness_clarity": JusticeState.rng.randf_range(0.4, 0.8) if witnessed else 0.0,
		"trace": JusticeState.rng.randf_range(float(k.get("trace_min", 0.15)), float(k.get("trace_max", 0.4))), "stolen_coins": take, "loot_value": take})
	CrimePlace.place_at_scene(culprit, lot_key)
	CrimeSecurityFootage.capture(c, lot_key, culprit)
	if witnessed:
		CaseDiscovery.report(c, -1, "seen")
	return {"text": "", "case": int(c["id"])}

# ------------------------------------------------------------------ full version (scene)
static func _start_scene(hid: int, culprit: int, forced: bool) -> Dictionary:
	var t: Dictionary = CrimePerson.rec(culprit)
	var existing = SysUtil.folk(culprit)
	var f = existing
	if f == null:
		var keep_next: int = Folk._next_id
		f = Folk.create(str(t["name"]), (t["traits"] as Array).duplicate(), culprit, Sexes.of_townie(t))
		Folk._next_id = keep_next
		f.household_id = -1
		f.age_stage = Story.stage_of(t)
		f.appearance = Genetics.normalize(Genetics.ensure(t))
		f.set_meta("visitor", true)
		f.set_meta("townie_id", culprit)
		RelationshipService.restore_folk(f)
		var entries: Array = CrimePlace.entry_points(hid)
		SysUtil.world_add_folk(f, entries[JusticeState.rng.randi_range(0, entries.size() - 1)])
	f.set_meta("burglar", true)
	f.add_buff("intruder")
	var k: Dictionary = cfg()
	var trace: float = JusticeState.rng.randf_range(float(k.get("trace_min", 0.15)), float(k.get("trace_max", 0.4)))
	var alarm: bool = false
	for o in Economy.objects_of(hid):
		if str(o.def_id) == "burglar_alarm":
			alarm = true
	var c: Dictionary = CaseStore.create("burglary", culprit, -1, "home:%d" % hid, {"trace": trace, "vhid": hid})
	c["on_scene"] = true
	c["alarm"] = alarm
	CrimePlace.place_at_scene(culprit, "home:%d" % hid)
	CrimeSecurityFootage.capture(c, "home:%d" % hid, culprit)
	# residents: awake ones notice at once, sleepers may wake
	var seen: Array = []
	for r in CrimePlace.at_home(hid):
		var wakes: bool = not CrimePlace.is_asleep(r) or JusticeState.chance(float(k.get("wake_chance", 0.3)))
		if wakes:
			if CrimePlace.is_asleep(r):
				r.cancel_current("woken")
			r.add_buff("intruder_alert")
			ThoughtVoice.urgent(int(r.id), "Was that a noise downstairs?")
			seen.append(int(r.id))
	c["witnesses"] = seen
	if not seen.is_empty():
		c["witnessed"] = true
		c["witness_clarity"] = clampf(0.5 + (0.2 if CrimePlace.lamp_on(hid) else 0.0) + JusticeState.rng.randf_range(0.0, 0.2), 0.0, 0.95)
		CaseStore.toast(c, "Someone is in the house! You can Confront them or Call the police.", "bad", true)
	if alarm:
		CaseStore.toast(c, "The burglar alarm is screaming!", "warn", true)
		CrimeSecurityAlarm.ring(c, "home:%d" % hid)      # a monitored alarm brings the police faster (task 21)
	var d: Dictionary = {"kind": "burgle_step", "case": int(c["id"]), "stage": "take", "due_min": SysUtil.now() + int(k.get("take_after_min", 4))}
	JusticeState.queue(d)
	SysUtil.game_event("burglary_started", {"case": int(c["id"]), "household_id": hid, "folk_id": culprit})
	return {"text": "", "case": int(c["id"])}

static func step(p: Dictionary) -> void:
	var c: Dictionary = CaseStore.get_case(int(p["case"]))
	if c.is_empty() or not bool(c.get("on_scene", false)):
		return
	var k: Dictionary = cfg()
	var b = SysUtil.folk(int(c["culprit"]))
	match str(p["stage"]):
		"take":
			var hid: int = int(c["vhid"])
			var vals: Array = CrimePlace.valuables(hid)
			if not vals.is_empty() and JusticeState.chance(float(k.get("item_vs_coins", 0.8))) and b != null and not CrimeLifeState.chance(float(CrimeSecurity.effects(CrimeSecurity.home_profile(hid))["safe_share"]) * 0.5):
				var ir := Interaction.create("burgle_item", b, int(vals[0].id), false)
				if ir != null:
					b.enqueue(ir)
				c["target_obj"] = int(vals[0].id)
			JusticeState.queue({"kind": "burgle_step", "case": int(c["id"]), "stage": "leave", "due_min": SysUtil.now() + int(k.get("leave_after_min", 6))})
		"leave":
			_take(c)
			if b != null:
				b.cancel_current("flee")
				b.clear_queue()
				var out := Interaction.create_goto(b, CrimePlace.entrance(), false)
				if out != null:
					b.enqueue(out)
			JusticeState.queue({"kind": "burgle_step", "case": int(c["id"]), "stage": "gone", "due_min": SysUtil.now() + int(k.get("gone_after_min", 5))})
		"gone":
			end_scene(c, false)

## The theft itself: an object (recorded so it can be recovered) or a share of the household's coins.
static func _take(c: Dictionary) -> void:
	if bool(c.get("took", false)):
		return
	c["took"] = true
	var hid: int = int(c["vhid"])
	var k: Dictionary = cfg()
	var oid: int = int(c.get("target_obj", -1))
	var o = WorldIface.get_object(oid) if oid >= 0 else null
	if o != null:
		var val: int = Economy.value_of(oid)
		var w = WorldIface.world()
		var rec: Dictionary = {"def": str(o.def_id), "tile": [o.tile.x, o.tile.y], "rot": int(o.rot), "value": val}
		if w != null and w.has_method("remove_object") and bool(w.remove_object(oid)):
			Economy.owner.erase(oid)
			(c["loot"] as Array).append(rec)
			c["loot_value"] = int(c["loot_value"]) + val
	else:
		var bal: int = int(float(WorldIface.get_coins(hid)) * (1.0 - float(CrimeSecurity.effects(CrimeSecurity.home_profile(hid))["safe_share"])))       # cash in a safe is out of reach (task 21)
		var amt: int = mini(bal, clampi(int(float(bal) * float(k.get("coin_share", 0.15))), int(k.get("coin_min", 20)), int(k.get("coin_max", 300))))
		if amt > 0:
			Economy.deposit(hid, -amt, "burglary")
			CrimePerson.add_coins(int(c["culprit"]), amt)
			c["stolen_coins"] = amt
	if (c["loot"] as Array).is_empty() and int(c["stolen_coins"]) <= 0:
		c["trace"] = float(c["trace"]) * 0.5

## The burglar leaves the map (or is caught). Witnessed crimes are reported now; hidden ones are found later.
static func end_scene(c: Dictionary, caught: bool) -> void:
	c["on_scene"] = false
	var b = SysUtil.folk(int(c["culprit"]))
	if b != null and b.has_meta("burglar"):
		b.remove_meta("burglar")
		b.remove_buff("intruder")
		if b.has_meta("visitor"):
			RelationshipService.sync_folk(b)
			b.cancel_current("left")
			b.clear_queue()
			SysUtil.world_remove_folk(int(b.id))
	for r in SysUtil.residents():
		r.remove_buff("intruder_alert")
	if str(c["state"]) == "hidden" and bool(c.get("witnessed", false)):
		var rep: int = int((c["witnesses"] as Array)[0]) if not (c["witnesses"] as Array).is_empty() else -1
		CaseDiscovery.report(c, rep, "seen")
		if not bool(c.get("called", false)):
			Police.respond(c, 30)
			c["on_scene"] = false
	elif str(c["state"]) == "hidden" and (not (c["loot"] as Array).is_empty() or int(c["stolen_coins"]) > 0):
		pass            # nobody saw: found when the owner next looks (CaseDiscovery)
	elif str(c["state"]) == "hidden":
		c["state"] = "closed"    # nothing was taken and nobody noticed
		CaseStore.note(c, "A break-in attempt left no trace.")

## Put the stolen goods back (police recovered them).
static func restore_loot(c: Dictionary) -> void:
	var hid: int = int(c["vhid"])
	var w = WorldIface.world()
	for it in c["loot"]:
		var placed: bool = false
		if w != null and w.has_method("place_object"):
			var tile := Vector2i(int(it["tile"][0]), int(it["tile"][1]))
			var nid: int = int(w.place_object(str(it["def"]), tile, int(it.get("rot", 0))))
			if nid > 0:
				Economy.owner[nid] = hid
				placed = true
		if not placed:
			Economy.deposit(hid, int(it["value"]), "goods recovered")
	c["loot"] = []
	if int(c["stolen_coins"]) > 0:
		Economy.deposit(hid, int(c["stolen_coins"]), "money recovered")
		CrimePerson.add_coins(int(c["culprit"]), -int(c["stolen_coins"]))
		c["stolen_coins"] = 0

# ------------------------------------------------------------------ player actions on a scene
## The resident confronts the intruder: the burglar may flee, someone may be hurt, extremely rarely someone dies.
static func on_confront(folk_id: int, target_id: int) -> Dictionary:
	var c: Dictionary = _scene_of(target_id)
	var f = SysUtil.folk(folk_id)
	if c.is_empty() or f == null:
		return {}
	var k: Dictionary = cfg().get("confront", {})
	var p: float = float(k.get("flee_base", 0.45)) + float(f.skill_level("fitness")) * float(k.get("fitness_bonus", 0.06))
	if f.has_trait("hot_headed"):
		p += 0.1
	if f.has_trait("active"):
		p += 0.05
	if f.has_trait("shy") or f.has_trait("clumsy"):
		p -= 0.12
	var res: Dictionary = {"fled": false, "hurt": -1, "died": -1}
	if JusticeState.chance(clampf(p, 0.1, 0.9)):
		res["fled"] = true
		CaseStore.toast(c, "%s shouted and the burglar fled!" % f.name, "good", true)
		if not bool(c.get("took", false)):
			c["target_obj"] = -1
			c["took"] = true                  # fled before taking anything
	else:
		var hurt: int = folk_id if JusticeState.chance(0.6) else target_id
		res["hurt"] = hurt
		if JusticeState.chance(float(k.get("death", 0.01))):
			res["died"] = hurt
			Aging.kill(hurt, "killed_in_fight")
			CaseStore.toast(c, "The struggle ended in tragedy.", "death", true)
		elif hurt == folk_id:
			Hospital.injure(f, 1, "a struggle with a burglar")
			CaseStore.toast(c, "%s was hurt in a struggle, and the burglar got away." % f.name, "bad", true)
		else:
			CaseStore.toast(c, "%s fought the burglar off, who ran away hurt." % f.name, "good", true)
	c["witnessed"] = true
	if not (c["witnesses"] as Array).has(folk_id):
		(c["witnesses"] as Array).append(folk_id)
	c["witness_clarity"] = maxf(float(c["witness_clarity"]), 0.8)
	end_scene(c, false)
	if str(c["state"]) == "hidden":
		CaseDiscovery.report(c, folk_id, "seen")
	return res

static func _scene_of(burglar_id: int) -> Dictionary:
	for c in CaseStore.in_state(["hidden", "open"]):
		if bool(c.get("on_scene", false)) and int(c["culprit"]) == burglar_id:
			return c
	return {}

# ------------------------------------------------------------------ guest theft
## Handler of incident `guest_theft`: a low-reputation guest pockets something. Hidden until the owner looks.
static func on_guest_theft(ctx: Dictionary, _args: Dictionary) -> Dictionary:
	if not enabled() or bool(ctx["statistical"]):
		return {"text": ""}
	var hid: int = int(ctx["household_id"])
	var best: int = -1
	var bw: float = 0.0
	for f in WorldIface.all_folk():
		if not f.has_meta("visitor") or f.has_meta("burglar") or not f.has_meta("townie_id"):
			continue
		var pid: int = int(f.get_meta("townie_id"))
		var w: float = 0.3 + clampf(-CrimePerson.reputation(pid) / 40.0, 0.0, 2.0) + (1.0 if CrimePerson.coins(pid) < 100 else 0.0)
		if CrimePerson.has_trait(pid, "honest"):
			w *= 0.05
		if w > bw:
			bw = w
			best = pid
	if best < 0 or not JusticeState.chance(clampf(bw / 3.0, 0.05, 0.9)) and not bool(ctx.get("forced", false)):
		return {"text": ""}
	var bal: int = WorldIface.get_coins(hid)
	var amt: int = mini(bal, JusticeState.rng.randi_range(15, 80))
	var loot: Array = []
	var vals: Array = CrimePlace.valuables(hid)
	var val: int = amt
	if not vals.is_empty() and JusticeState.chance(0.5):
		var o = vals[vals.size() - 1]
		var rec: Dictionary = {"def": str(o.def_id), "tile": [o.tile.x, o.tile.y], "rot": int(o.rot), "value": Economy.value_of(int(o.id))}
		var w2 = WorldIface.world()
		if w2 != null and w2.has_method("remove_object") and bool(w2.remove_object(int(o.id))):
			Economy.owner.erase(int(o.id))
			loot.append(rec)
			val = int(rec["value"])
			amt = 0
	if amt <= 0 and loot.is_empty():
		return {"text": ""}
	if amt > 0:
		Economy.deposit(hid, -amt, "stolen by a guest")
		CrimePerson.add_coins(best, amt)
	var c: Dictionary = CaseStore.create("theft", best, -1, "home:%d" % hid, {"loot": loot, "stolen_coins": amt, "loot_value": val, "trace": 0.3, "vhid": hid,
		"witness_clarity": 0.0})
	c["guest"] = true
	c["witnesses"] = []
	CrimePlace.place_at_scene(best, "home:%d" % hid)
	return {"text": "", "case": int(c["id"])}
