class_name CoopCommands
extends RefCounted
## Host-side command handling. Envelope: {player_id, folk_id, action, args, game_minute, seq} (CoopProto.CMD).
##
## THE ADAPTER: `apply()` is the ONLY place in the co-op code that knows the sim API: it converts an envelope into a Commands.run call
## (scripts/sim/commands.gd, the one command layer the UI uses too). Validation, acks and idempotence stay here.
##
## Allowlist (stage 2): the Players table. A player may command a folk only when the folk's household is the household Players maps
## them to (`allowed`). `allow` is an optional OVERRIDE (player id -> household ids) used by tests; empty = use the Players table.
## Tiles travel as {"_v": [x, y]} (the wire only carries plain data); `to_wire` / `from_wire` convert.

static var allow: Dictionary = {}
## action -> what the first check looks at: "folk" (folk_id must be yours), "folks" (args.folk_ids all yours), "build" (needs a household), "bill"
const ACTIONS := {
	"interact": "folk", "career_accept": "folk", "career_decline": "folk", "career_skip": "folk", "career_unskip": "folk", "set_aspiration": "folk",
	"travel": "folks", "go_home": "folks", "build_place": "build", "build_sell": "build", "build_wall": "build", "build_floor": "build",
	"pay_bill": "bill",
}
const EXTRA_KEYS := ["tile", "level"]

static func set_allowlist(a: Dictionary) -> void:
	allow = a.duplicate(true)

static func households_of(player_id: int) -> Array:
	if not allow.is_empty():
		return allow.get(player_id, [])
	var h := Players.household_of(player_id)
	return [h] if h > 0 else []

static func allowed(player_id: int, folk_id: int) -> bool:
	var f = WorldIface.get_folk(folk_id)
	return f != null and households_of(player_id).has(int(f.household_id))

# ------------------------------------------------------------------ wire form of arguments
static func to_wire(v: Variant) -> Variant:
	match typeof(v):
		TYPE_VECTOR2I:
			return {"_v": [v.x, v.y]}
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[str(k)] = to_wire(v[k])
			return d
		TYPE_ARRAY:
			var a := []
			for x in v:
				a.append(to_wire(x))
			return a
	return v

static func from_wire(v: Variant) -> Variant:
	if v is Dictionary:
		var d: Dictionary = v
		if d.size() == 1 and d.has("_v") and d["_v"] is Array and (d["_v"] as Array).size() == 2:
			return Vector2i(int(d["_v"][0]), int(d["_v"][1]))
		var out := {}
		for k in d:
			out[k] = from_wire(d[k])
		return out
	if v is Array:
		var a := []
		for x in v:
			a.append(from_wire(x))
		return a
	return v

## Validate (but do not run) an envelope. Returns "" when fine, else a plain-language reason for the player.
static func check(env: Dictionary) -> String:
	var action := str(env.get("action", ""))
	if not ACTIONS.has(action):
		return "That action is not available in co-op yet."
	var pid := int(env.get("player_id", -1))
	if households_of(pid).is_empty():
		return "You have no household yet."
	var args: Dictionary = from_wire(env.get("args", {}))
	match str(ACTIONS[action]):
		"folk":
			if WorldIface.get_folk(int(env.get("folk_id", -1))) == null:
				return "That person is not in the town any more."
			if not allowed(pid, int(env.get("folk_id", -1))):
				return "You can only give orders to your own household."
		"folks":
			var ids: Variant = args.get("folk_ids", [])
			if not (ids is Array) or (ids as Array).is_empty():
				return "Nobody was chosen."
			for x in ids:
				if typeof(x) != TYPE_INT or not allowed(pid, int(x)):
					return "You can only give orders to your own household."
		"build":
			if action == "build_sell" and not _own_object(pid, int(args.get("object_id", -1))):
				return "You can only sell things on your own lot."
	if action == "interact":
		var extra: Variant = args.get("extra", {})
		if not (extra is Dictionary):
			return "Bad target."
		for k in extra:
			if not EXTRA_KEYS.has(str(k)):
				return "Bad target."
		if (extra as Dictionary).has("tile"):
			if typeof(extra["tile"]) != TYPE_VECTOR2I:
				return "Bad target."
		else:
			var iid: Variant = args.get("interaction_id", null)
			if typeof(iid) != TYPE_STRING or not SimEnv.data().interactions().has(iid):
				return "Unknown activity."
		if typeof(args.get("target_id", -1)) != TYPE_INT:
			return "Bad target."
	return ""

static func _own_object(pid: int, object_id: int) -> bool:
	var o = WorldIface.get_object(object_id)
	var w = WorldIface.world()
	if o == null or w == null or not ("regions" in w):
		return false
	return PlayerLots.region_owner(w.regions.region_of(o.tile)) == pid

## Run a validated envelope on the host's sim through the command layer. Returns {"ok": bool, "msg": String}.
static func apply(env: Dictionary) -> Dictionary:
	var why := check(env)
	if why != "":
		return {"ok": false, "msg": why}
	var action := str(env["action"])
	var pid := int(env["player_id"])
	var args: Dictionary = from_wire(env.get("args", {}))
	if action == "interact":
		args = {"interaction_id": str(args.get("interaction_id", "")), "target_id": int(args.get("target_id", -1)),
			"extra": args.get("extra", {}), "strict": bool(args.get("strict", true))}
	elif action == "pay_bill":
		args = {"household_id": Players.household_of(pid)}
	var res: Dictionary = Commands.run({"player_id": pid, "folk_id": int(env.get("folk_id", -1)), "action": action,
		"game_minute": int(env.get("game_minute", SimEnv.now_min())), "args": args})
	return {"ok": bool(res.get("ok", false)), "msg": str(res.get("msg", ""))}
