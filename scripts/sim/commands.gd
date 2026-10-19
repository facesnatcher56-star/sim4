class_name Commands
extends RefCounted
## THE command layer (multiplayer-ready rule 24A.1): every player action is `Commands.run({player_id, folk_id, action, args, game_minute})` ->
## {ok, msg, ...}. The UI never mutates sim state directly; the co-op adapter (CoopCommands.apply) and tests call the same door.
## Every command is logged (bounded ring buffer) with the game minute and a running `seq`, so a session can be replayed on a fresh game from the
## same seed (`replay`), undone or sent over a wire. Handlers live in command_actions.gd (one small function per action).
##
## Actions (args): interact {interaction_id, target_id, extra, strict} | build_place {def_id, tile, rot, level} | build_sell {object_id} |
## build_wall {a, b, type, level} | build_floor {a, b, type, level} | build_undo | career_accept | career_decline | career_skip | career_unskip |
## travel {folk_ids, lot_id, opts} | go_home {folk_ids, opts} | pay_bill {household_id} | set_aspiration {aspiration} | invite_to_venue {townie_id, lot_id} |
## prison_visit {inmate} | market {action, args} (MarketCommand) | vacation {action, args} (Vacation.command) | set_heir {heir_id} | choose_successor {choice, household} (SuccessionCmd) | pregnancy {action: name_baby|labour_place|bed_rest|fertility_treatment, ...} (PregnancyCmd) | crimelife {action: join|leave|job|case|plan|abort|recruit|drop_crew|getaway|go|gear|fence|biz_upgrade|home_service, ...} (CrimeLifeCmd) | city {action, args} (CityCmd: buy_car, sell_car, refuel, repair_car, collect_car, buy_bike, bus_times) | crimeunder {action: line_join|line_leave|hit_*|deal_*|rehab|racket_*|gang_*|cop_*|intervene|redeem_*, ...} (CrimeUnderCmd).
## Not commands: speed / pause (host policy), settings, save / load slots, camera and selection (view state).

const LOG_CAP := 500
static var log: Array = []             # [{seq, player_id, folk_id, action, args, game_minute, ok}] oldest first, at most LOG_CAP
static var seq: int = 0
## Set on a co-op client: Callable(envelope) -> {ok, msg, pending}. Commands are then sent to the host instead of run here.
static var remote: Callable = Callable()

static func reset() -> void:
	log.clear()
	seq = 0

static func run(env: Dictionary) -> Dictionary:
	var e: Dictionary = {
		"player_id": int(env.get("player_id", Players.local_id)),
		"folk_id": int(env.get("folk_id", -1)),
		"action": str(env.get("action", "")),
		"args": (env.get("args", {}) as Dictionary).duplicate(true) if env.get("args", {}) is Dictionary else {},
		"game_minute": int(env.get("game_minute", SimEnv.now_min())),
	}
	if remote.is_valid():        # a co-op client: the order goes to the host, which runs it (CoopClient.send_command via CoopRemote)
		return remote.call(e)
	seq += 1
	e["seq"] = seq
	var res: Dictionary
	if not CommandActions.has_action(e["action"]):
		res = {"ok": false, "msg": "That action is not available."}
	else:
		PlayerLots.acting = int(e["player_id"])        # build rules follow the player whose order this is
		res = CommandActions.dispatch(e)
		PlayerLots.acting = -1
		if not res.has("ok"):
			res["ok"] = true
	var entry: Dictionary = e.duplicate()
	entry["ok"] = bool(res.get("ok", false))
	log.append(entry)
	while log.size() > LOG_CAP:
		log.pop_front()
	return res

## Commands since `from_seq` (exclusive), as plain dictionaries ready to replay.
static func since(from_seq: int = 0) -> Array:
	var out: Array = []
	for e in log:
		if int(e["seq"]) > from_seq:
			out.append((e as Dictionary).duplicate(true))
	return out

## Re-run a recorded session: before each command the clock is advanced to its game minute with `advance` (Callable(minutes_to_advance) that
## steps the real sim, e.g. HoodKit.run), then the command runs. Failed originals are replayed too (they fail the same way). Returns the results.
static func replay(entries: Array, advance: Callable) -> Array:
	var out: Array = []
	for e in entries:
		var now: int = SimEnv.now_min()
		var due: int = int(e["game_minute"])
		if due > now and advance.is_valid():
			advance.call(due - now)
		out.append(run({"player_id": e["player_id"], "folk_id": e["folk_id"], "action": e["action"], "args": e["args"], "game_minute": due}))
	return out
