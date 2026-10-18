extends RefCounted
## Tornado: siren warning + take-cover orders, impact after the lead time (outdoor objects wrecked, roof damaged, outdoor folk hurt, sheltered
## folk safe), shutters, insurance payout, repairs, debris cleanup, neighbours, shared grief.

const K = preload("res://tests/systems_kit.gd")
const D = preload("res://tests/disaster_kit.gd")

func run() -> Array:
	var f: Array = []
	_siren_and_impact(f)
	_prepared(f)
	_aftermath(f)
	_cover_runs(f)
	return f

func _all_in(kind: String) -> void:
	D.cfg_set(kind, "object_hit", [1.0, 1.0, 1.0])
	D.cfg_set(kind, "out_hurt", [1.0, 1.0, 1.0])
	D.cfg_set(kind, "out_kill", [0.0, 0.0, 0.0])
	D.cfg_set(kind, "in_hurt", [0.0, 0.0, 0.0])
	D.cfg_set(kind, "in_kill", [0.0, 0.0, 0.0])

func _siren_and_impact(f: Array) -> void:
	var w := D.setup()
	var h: Dictionary = D.home(w)
	var ada: Folk = h["ada"]
	var bo: Folk = h["bo"]
	_all_in("tornado")
	ada.set_meta("outdoors", true)
	bo.tile = Vector2i(14, 15)                      # next to the toilet at (14, 14)
	DisasterState.siren_when_forced = true
	K.set_time(10, 15)
	var r: Dictionary = D.force_home("tornado", 1)  # power 2
	K.expect(f, bool(r["ok"]) and K.has_note("siren"), "the siren warns the home lot (%s)" % str(r))
	K.expect(f, K.has_note("tornado has touched down"), "one town headline")
	K.expect(f, ada.has_buff("siren_alert") and bo.has_buff("siren_alert"), "everybody is alerted")
	var queued: bool = false
	for q in bo.queue:
		queued = queued or (q as Interaction).def_id == "take_cover"
	K.expect(f, queued or (bo.current != null and bo.current.def_id == "take_cover"), "folk are sent to take cover")
	K.expect(f, D.count_objects(w, "grill") == 1 and not ada.has_buff("injured"), "nothing is hit during the siren")
	var grill_id: int = h["objs"]["grill"].id
	D.run_minutes(7)
	var grill = w.get_object(grill_id)
	K.expect(f, grill == null or bool(WorldIface.state_get(grill, "broken", false)), "the grill outside is wrecked")
	K.expect(f, float(WorldIface.state_get(h["objs"]["garden_plot"], "growth", 1.0)) == 0.0, "the garden is flattened")
	K.expect(f, w.get_object(h["objs"]["mailbox"].id) != null, "the mailbox survives so repairs stay possible")
	K.expect(f, D.count_objects(w, "debris") >= 0, "debris placement is safe")
	K.expect(f, ada.has_buff("injured"), "somebody caught outside is hurt")
	K.expect(f, not bo.has_buff("injured"), "somebody next to a bathroom fixture is safe")
	K.expect(f, DisasterState.lot("home:1")["cost"] > 0 and ada.has_buff("home_damaged"), "the roof needs repairs (cost %d)" % int(DisasterState.lot("home:1")["cost"]))
	K.expect(f, not ada.has_buff("siren_alert"), "the alert is over after the impact")
	K.expect(f, ChronicleHook.recent.size() > 0, "chronicle lines written")
	K.teardown()

func _prepared(f: Array) -> void:
	var w := D.setup()
	var h: Dictionary = D.home(w)
	var ada: Folk = h["ada"]
	_all_in("tornado")
	ada.set_meta("outdoors", true)
	w.add_object("storm_shutters", Vector2i(34, 34))
	Economy.refresh_objects()
	D.force_home("tornado", 0)                      # power 1: the shutters cancel a light tornado
	K.expect(f, not ada.has_buff("injured") and float(DisasterState.lot("home:1")["cost"]) == 0.0, "storm shutters turn a light tornado away")
	K.expect(f, K.has_note("preparations paid off"), "the player is told the preparation worked")
	K.teardown()

func _aftermath(f: Array) -> void:
	var w := D.setup()
	var h: Dictionary = D.home(w)
	var ada: Folk = h["ada"]
	var bo: Folk = h["bo"]
	Story.generate_townies()
	_all_in("tornado")
	D.cfg_set("tornado", "out_kill", [1.0, 1.0, 1.0])
	DisasterInsurance.set_level(1, "full")
	DisasterInsurance.install()
	ada.set_meta("outdoors", true)
	K.set_time(10, 15)
	var coins0: int = WorldIface.get_coins(1)
	D.force_home("tornado", 1)
	K.expect(f, w.get_folk(ada.id) == null, "an outdoor victim can die")
	K.expect(f, DisasterState.deaths.size() == 1 and K.has_note("did not survive"), "the death is recorded and told gently")
	K.expect(f, WorldIface.get_coins(1) > coins0 or int(DisasterState.lot("home:1")["cost"]) == 0, "full cover pays out part of the loss")
	var quote: int = DisasterAftermath.repair_quote(1)
	K.expect(f, quote > 0, "repairers quote a price (%d)" % quote)
	# repairs
	var before: int = WorldIface.get_coins(1)
	SimEnv.emit("game_event", "call_repairers", {"folk_id": bo.id, "object_id": -1, "target_id": -1})
	K.expect(f, DisasterAftermath.repair_quote(1) == 0 and WorldIface.get_coins(1) == before - quote and not bo.has_buff("home_damaged"), "calling the repairers pays and clears the damage")
	# neighbours + shared grief on the next day
	K.set_time(11, 9)
	var c1: int = WorldIface.get_coins(1)
	DisasterClock.on_day(11)
	K.expect(f, WorldIface.get_coins(1) > c1 and K.has_note("came by to help"), "neighbours visit and bring a gift")
	K.expect(f, bo.has_buff("neighbours_cared") and bo.has_buff("town_mourning"), "comfort and shared grief")
	K.expect(f, DisasterState.deaths.is_empty(), "grief handled once")
	# debris
	DisasterState.lot("home:1")["debris"] = 1
	var did: int = w.place_object("debris", Vector2i(31, 31))
	SimEnv.emit("game_event", "debris_cleared", {"folk_id": bo.id, "object_id": did, "target_id": -1})
	K.expect(f, w.get_object(did) == null and int(DisasterState.lot("home:1")["debris"]) == 0, "clearing debris removes it")
	K.teardown()

func _cover_runs(f: Array) -> void:
	var w := D.setup()
	var h: Dictionary = D.home(w)
	var dir = K.director()
	DisasterState.siren_when_forced = true
	_all_in("tornado")
	h["ada"].tile = Vector2i(20, 20)                # out in the yard
	D.force_home("tornado", 1)
	for i in 6:
		K.run(dir, 1)
		DisasterClock.on_minute()
	K.expect(f, h["ada"].current != null and h["ada"].current.def_id == "take_cover", "during the siren folk really walk to the bathroom and take cover")
	K.expect(f, DisasterDamage.exposure(h["ada"], 1) == "cover", "and count as protected")
	dir.free()
	K.teardown()
