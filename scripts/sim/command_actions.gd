class_name CommandActions
extends RefCounted
## Handlers of the command layer (see commands.gd): each takes the normalised envelope and returns {ok, msg, ...}. Keep them thin: they only call
## the existing sim API; no UI, no view state.

const HANDLERS := {
	"interact": "_interact", "build_place": "_build_place", "build_sell": "_build_sell", "build_wall": "_build_wall", "build_floor": "_build_floor",
	"build_undo": "_build_undo", "career_accept": "_career_accept", "career_decline": "_career_decline", "career_skip": "_career_skip",
	"career_unskip": "_career_unskip", "set_homemaker": "_set_homemaker", "travel": "_travel", "go_home": "_go_home", "pay_bill": "_pay_bill", "set_aspiration": "_set_aspiration",
	"invite_to_venue": "_invite", "prison_visit": "_prison_visit", "market": "_market", "vacation": "_vacation", "life": "_life",
	"set_heir": "_set_heir", "choose_successor": "_choose_successor", "pregnancy": "_pregnancy", "crimelife": "_crimelife", "city": "_city", "crimeunder": "_crimeunder", "storyteller": "_storyteller",
	"works": "_works", "solo": "_solo",
}

static func has_action(action: String) -> bool:
	return HANDLERS.has(action)

static func dispatch(e: Dictionary) -> Dictionary:
	return Callable(CommandActions, HANDLERS[e["action"]]).call(e)

static func _hid(e: Dictionary) -> int:
	var h: int = Players.household_of(int(e["player_id"]))
	return h if h > 0 else -1

static func _world():
	return WorldIface.world()

static func _director():
	var ml := Engine.get_main_loop()
	return (ml as SceneTree).root.get_node_or_null("SimDirector") if ml is SceneTree else null

# ------------------------------------------------------------------ doing things
## args: interaction_id, target_id (-1), extra ({tile, level} = walk there; other keys merge into the interaction params), strict (true: the
## director's check, the co-op door - refuses what cannot run now; false: queue it with player priority, as the pie menu always did).
static func _interact(e: Dictionary) -> Dictionary:
	var a: Dictionary = e["args"]
	var f = WorldIface.get_folk(int(e["folk_id"]))
	if f == null:
		return {"ok": false, "msg": "That person is not in the town any more."}
	if Players.owns(int(e.get("player_id", Players.LOCAL)), int(f.household_id)) and not Pawn.is_pawn(f) and not Players.table.is_empty():
		return {"ok": false, "msg": "You play one character. %s makes their own choices." % str(f.name)}
	if bool(a.get("strict", false)):
		var sd = _director()
		if sd == null:
			return {"ok": false, "msg": "The host's game is not running."}
		var ok: bool = sd.command(int(e["folk_id"]), str(a.get("interaction_id", "")), int(a.get("target_id", -1)))
		return {"ok": ok, "msg": "" if ok else "That can't be done right now."}
	var extra: Dictionary = a.get("extra", {})
	var it = null
	if extra.has("tile"):
		_replace_walk(f)          # a new click to walk somewhere replaces the last one: it never queues several trips
		it = Interaction.create_goto(f, extra["tile"], true, int(extra.get("level", 0)))
	else:
		it = Interaction.create(str(a.get("interaction_id", "")), f, int(a.get("target_id", -1)), true)
	if it == null:
		return {"ok": false, "msg": "That can't be done right now."}
	if extra.size() > 0 and it.get("params") is Dictionary:
		it.params.merge(extra, true)
	if f.has_method("enqueue"):
		f.enqueue(it)
	else:
		f.queue.append(it)
		SimEnv.events().queue_changed.emit(int(f.id))
	var sd = _director()
	if sd != null and sd.has_method("start_now"):
		sd.start_now(f)          # task 58: the order starts in this frame, not on the next game minute (a pre-empted one was cancelled by enqueue)
	return {"ok": true, "msg": ""}

## The player's last "go here" is cancelled (the one running and any waiting); other queued orders and the job commute stay.
static func _replace_walk(f) -> void:
	if f.current != null and f.current.def_id == "go_here" and f.current.player and not f.current.params.has("commute"):
		f.current.cancel("replaced")
	for q in f.queue.duplicate():
		if (q as Interaction).def_id == "go_here" and (q as Interaction).player and not (q as Interaction).params.has("commute"):
			f.queue.erase(q)

static func _build_place(e: Dictionary) -> Dictionary:
	var a: Dictionary = e["args"]
	var w = _world()
	var id: int = w.buy_place(str(a.get("def_id", "")), a["tile"], int(a.get("rot", 0)), _hid(e), int(a.get("level", 0)))
	return {"ok": id >= 0, "id": id, "msg": "" if id >= 0 else str(w.last_error)}

static func _build_sell(e: Dictionary) -> Dictionary:
	var w = _world()
	var ok: bool = w.sell_object(int(e["args"].get("object_id", -1)), _hid(e))
	return {"ok": ok, "msg": "" if ok else str(w.last_error)}

static func _build_wall(e: Dictionary) -> Dictionary:
	var a: Dictionary = e["args"]
	var w = _world()
	var permit: Dictionary = CityPolicy.pay_permit(_hid(e), "build")        # task 12: a building permit, only when the council has voted for permits
	if not bool(permit["ok"]):
		return {"ok": false, "n": 0, "msg": str(permit["reason"])}
	var n: int = w.set_wall_line(a["a"], a["b"], str(a.get("type", "wall")), _hid(e), int(a.get("level", 0)))
	return {"ok": n > 0, "n": n, "msg": "" if n > 0 else str(w.last_error)}

static func _build_floor(e: Dictionary) -> Dictionary:
	var a: Dictionary = e["args"]
	var w = _world()
	var n: int = w.paint_floor_rect(a["a"], a["b"], str(a.get("type", "")), _hid(e), int(a.get("level", 0)))
	return {"ok": n > 0, "n": n, "msg": "" if n > 0 else str(w.last_error)}

static func _build_undo(_e: Dictionary) -> Dictionary:
	return {"ok": bool(_world().undo_last())}

static func _career_accept(e: Dictionary) -> Dictionary:
	return {"ok": bool(Careers.accept_offer(int(e["folk_id"])))}

static func _career_decline(e: Dictionary) -> Dictionary:
	Careers.decline_offer(int(e["folk_id"]))
	return {"ok": true}

static func _career_skip(e: Dictionary) -> Dictionary:
	Careers.skip_work_today(int(e["folk_id"]))
	return {"ok": true}

static func _set_homemaker(e: Dictionary) -> Dictionary:
	var f = SysUtil.folk(int(e["folk_id"]))
	return {"ok": Homemaker.set_role(f, bool((e.get("args", {}) as Dictionary).get("on", true)))}

static func _career_unskip(e: Dictionary) -> Dictionary:
	Careers.skip_flags.erase(int(e["folk_id"]))
	return {"ok": true}

static func _travel(e: Dictionary) -> Dictionary:
	var a: Dictionary = e["args"]
	return Neighborhood.travel(a.get("folk_ids", []), str(a.get("lot_id", "")), a.get("opts", {}))

static func _go_home(e: Dictionary) -> Dictionary:
	var a: Dictionary = e["args"]
	var lot: String = PlayerLots.lot_of(int(e["player_id"]))      # each co-op player's own lot
	return Neighborhood.travel(a.get("folk_ids", []), lot if lot != "" else Neighborhood.HOME, a.get("opts", {}))

static func _pay_bill(e: Dictionary) -> Dictionary:
	var hid: int = int(e["args"].get("household_id", _hid(e)))
	Economy.pay_bill(hid)
	return {"ok": true}

static func _set_aspiration(e: Dictionary) -> Dictionary:
	return {"ok": bool(Goals.set_aspiration(int(e["folk_id"]), str(e["args"].get("aspiration", ""))))}

static func _invite(e: Dictionary) -> Dictionary:
	var a: Dictionary = e["args"]
	var rec: Dictionary = Story.invite_to_venue(int(a.get("townie_id", -1)), int(e["folk_id"]), str(a.get("lot_id", "")))
	return {"ok": not rec.is_empty(), "rec": rec}

static func _prison_visit(e: Dictionary) -> Dictionary:
	return {"ok": bool(Prison.visit(int(e["folk_id"]), int(e["args"].get("inmate", -1))))}

static func _market(e: Dictionary) -> Dictionary:
	var a: Dictionary = e["args"]
	return MarketCommand.run(int(e["player_id"]), int(e["folk_id"]), str(a.get("action", "")), a.get("args", {}))

static func _city(e: Dictionary) -> Dictionary:
	return CityCmd.run(e)

static func _life(e: Dictionary) -> Dictionary:
	var a: Dictionary = e["args"]
	return LifeCommand.run(int(e["player_id"]), int(e["folk_id"]), str(a.get("action", "")), a.get("args", {}))

static func _set_heir(e: Dictionary) -> Dictionary:
	return SuccessionCmd.set_heir(e)

static func _pregnancy(e: Dictionary) -> Dictionary:
	return PregnancyCmd.run(e)

static func _crimelife(e: Dictionary) -> Dictionary:
	return CrimeLifeCmd.run(e)

static func _solo(e: Dictionary) -> Dictionary:
	return SoloCmd.run(e)

static func _works(e: Dictionary) -> Dictionary:
	return WorksCmd.run(e)

static func _storyteller(e: Dictionary) -> Dictionary:
	return StorytellerCmd.run(e)

static func _crimeunder(e: Dictionary) -> Dictionary:
	return CrimeUnderCmd.run(e)

static func _choose_successor(e: Dictionary) -> Dictionary:
	return SuccessionCmd.choose_successor(e)

static func _vacation(e: Dictionary) -> Dictionary:
	var a: Dictionary = e["args"]
	return Vacation.command({"player_id": e["player_id"], "folk_id": e["folk_id"], "action": a.get("action", ""), "args": a.get("args", {}), "game_minute": e["game_minute"]})
