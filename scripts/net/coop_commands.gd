class_name CoopCommands
extends RefCounted
## Host-side command handling. Envelope: {player_id, folk_id, action, args, game_minute, seq} (CoopProto.CMD).
##
## THE ADAPTER: `apply()` is the ONLY place in the co-op code that knows the sim API. Today it calls
## SimDirector.command(folk_id, interaction_id, target_id). After the scheduler / command layer (17.2) lands, only the
## body of `apply()` (and `_sim_director()`) changes; validation, acks, idempotence and the allowlist stay as they are.
##
## Allowlist (stage 1): a player may command a folk only when the folk's household is in `allow[player_id]`. Stage 2 (the
## players table, player id -> household id) replaces `allow` with a lookup; nothing else needs to change.

## player id -> household ids that player may command. Players 2..4 are clients; the host (1) plays locally.
static var allow: Dictionary = {2: [1], 3: [1], 4: [1]}
const ACTIONS := ["interact"]        # actions the adapter understands (args: interaction_id: String, target_id: int)

static func set_allowlist(a: Dictionary) -> void:
	allow = a.duplicate(true)

static func allowed(player_id: int, folk_id: int) -> bool:
	var f = WorldIface.get_folk(folk_id)
	if f == null:
		return false
	var hs: Array = allow.get(player_id, [])
	return hs.has(int(f.household_id))

## Validate (but do not run) an envelope. Returns "" when fine, else a plain-language reason for the player.
static func check(env: Dictionary) -> String:
	var action := str(env.get("action", ""))
	if not ACTIONS.has(action):
		return "That action is not available in co-op yet."
	if WorldIface.get_folk(int(env.get("folk_id", -1))) == null:
		return "That person is not in the town any more."
	if not allowed(int(env.get("player_id", -1)), int(env.get("folk_id", -1))):
		return "You can only give orders to your own household."
	var args: Dictionary = env.get("args", {})
	if action == "interact":
		var iid: Variant = args.get("interaction_id", null)
		if typeof(iid) != TYPE_STRING or not SimEnv.data().interactions().has(iid):
			return "Unknown activity."
		if typeof(args.get("target_id", -1)) != TYPE_INT:
			return "Bad target."
	return ""

## Run a validated envelope on the host's sim. Returns {"ok": bool, "msg": String}.
static func apply(env: Dictionary) -> Dictionary:
	var why := check(env)
	if why != "":
		return {"ok": false, "msg": why}
	var args: Dictionary = env.get("args", {})
	var sd = _sim_director()
	if sd == null:
		return {"ok": false, "msg": "The host's game is not running."}
	var ok: bool = sd.command(int(env["folk_id"]), str(args["interaction_id"]), int(args.get("target_id", -1)))
	return {"ok": ok, "msg": "" if ok else "That can't be done right now."}

static func _sim_director():
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null("SimDirector")
	return null
