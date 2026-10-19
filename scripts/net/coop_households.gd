class_name CoopHouseholds
extends RefCounted
## Host side of "a joining player creates their household" (co-op stage 2). The client sends its household description (HouseholdSetup
## dictionary as JSON, CoopProto.HOUSEHOLD); `join()` sanitises it (the client is not trusted), gives the player a free home lot
## (PlayerLots.claim: a converted townie home), creates the Folk on that lot's spawn tiles, registers them with the systems, gives the
## household its starting funds and puts the player into the Players table. Everything happens in ONE function so a test (or a late
## joiner, mid-game) runs the very same code. Returns {ok, msg, hid, lot, folk_ids}.

const MAX_NAME := 16
const START_FUNDS_FALLBACK := 5000

static func parse(bytes: PackedByteArray) -> Dictionary:
	return CoopLive.unpack_json(bytes)

static func pack(h: Dictionary) -> PackedByteArray:
	return CoopLive.pack_json(h)

static func _clean(s: String, max_len: int, fallback: String) -> String:
	var out := ""
	for ch in s.strip_edges():
		if ch.unicode_at(0) >= 32 and ch.unicode_at(0) != 127:
			out += ch
	out = out.strip_edges().left(max_len)
	return out if out != "" else fallback

## A safe copy of a client's household: known fields only, valid ids, bounded sizes. Never trusts the input.
static func sanitize(h: Dictionary) -> Dictionary:
	var out_folk: Array = []
	var used: Array = []
	var looks: Array = []
	var traits_ok: Array = SimEnv.data().traits().keys()
	var raw_folk: Variant = h.get("folk", [])
	if not (raw_folk is Array):
		return {}
	for i in mini((raw_folk as Array).size(), HouseholdSetup.MAX_FOLK):
		var fd: Variant = raw_folk[i]
		if not (fd is Dictionary):
			continue
		var stage := str(fd.get("stage", "adult"))
		if not HouseholdSetup.STAGES.has(stage):
			stage = "adult"
		var nm := _clean(str(fd.get("name", "")), MAX_NAME, "")
		if nm == "" or used.has(nm.to_lower()):
			nm = HouseholdSetup.random_name(used)
		used.append(nm.to_lower())
		var traits: Array = []
		for t in (fd.get("traits", []) if fd.get("traits", []) is Array else []):
			if traits_ok.has(str(t)) and not traits.has(str(t)) and traits.size() < 3:
				traits.append(str(t))
		var look: Variant = fd.get("appearance", {})
		if not (look is Dictionary) or not Genetics.is_valid(look):
			look = Genetics.unique_appearance(looks + GeneticsUnique.registry(), HouseholdSetup.rng_or_new(null))
		looks.append(look)
		var rel := str(fd.get("rel", "none"))
		var asp := str(fd.get("aspiration", ""))
		var sx := str(fd.get("sex", ""))
		out_folk.append({"name": nm, "sex": sx if Sexes.valid(sx) else Sexes.guess(nm, 0), "stage": stage, "traits": traits, "aspiration": asp if asp.length() < 40 else "",
			"appearance": (look as Dictionary).duplicate(true), "rel": rel if HouseholdSetup.REL_ORDER.has(rel) else "none"})
	if not out_folk.is_empty():
		out_folk[0]["rel"] = "none"
	return {"name": _clean(str(h.get("name", "")), 20, "Household"), "folk": out_folk}

static func join(player_id: int, player_name: String, raw_household: Dictionary, lot_id: String = "") -> Dictionary:
	var fail := func(msg: String) -> Dictionary: return {"ok": false, "msg": msg, "hid": -1, "lot": "", "folk_ids": []}
	if player_id <= Players.LOCAL or Players.table.has(player_id):
		return fail.call("You already have a household.")
	var h := sanitize(raw_household)
	if h.is_empty():
		return fail.call("That household could not be read.")
	var err := HouseholdSetup.validate(h)
	if err != "":
		return fail.call(err)
	var claim := PlayerLots.claim(player_id, lot_id)
	if not bool(claim["ok"]):
		return fail.call(str(claim["msg"]))
	var w = WorldIface.world()
	var lot: String = str(claim["lot"])
	var hid := Players.new_household_id()
	var folk: Array = HouseholdSetup.create_folk(h)
	var spawns: Array = PlayerLots.spawns(lot)
	var tiles: Array = HouseholdSetup.spawn_tiles(folk.size(), spawns)
	var ids: Array = []
	for i in folk.size():
		folk[i].household_id = hid
		w.add_folk(folk[i], tiles[i])
		ids.append(int(folk[i].id))
	Players.set_player(player_id, hid, _clean(player_name, 24, "Player %d" % player_id))
	var mgr: SystemsManager = SystemsManager.instance
	if mgr != null:
		mgr.ensure_registered()
	Economy.start_funds(hid)
	HouseholdSetup.apply(h, folk)
	PlayerLots.hand_over_objects(lot, hid)
	SysUtil.game_event("moved_in", {"folk_id": ids[0], "household_id": hid, "player_id": player_id})
	return {"ok": true, "msg": "", "hid": hid, "lot": lot, "folk_ids": ids}

## What a joining player may choose from: ready-made households (scenario presets) and the lots still free.
static func presets(count: int = 3) -> Array:
	var out: Array = []
	var ids: Array = Scenario.ids()
	for sid in ids:
		if out.size() >= count:
			break
		var d: Dictionary = Scenario.def(str(sid))
		if bool(d.get("custom", false)):
			continue
		out.append({"scenario": str(sid), "label": str(d.get("label", sid)), "household": HouseholdSetup.make_household(str(sid))})
	if out.is_empty():
		out.append({"scenario": "", "label": "A new household", "household": HouseholdSetup.make_household("")})
	return out
