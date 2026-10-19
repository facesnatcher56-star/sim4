class_name Players
extends RefCounted
## The `players` table (multiplayer-ready rule 24A.5): player id -> {household_id, name}. Even with one player nothing may assume "household 1 is the
## player": ask Players. Player LOCAL (1) is the local / host player. Without an explicit entry (old saves, tests that never registered anyone) the
## local player's household falls back to the World's current household, else the first household that has folk, else 1 (the old behaviour).
##
## Saved in the "players" block of SaveLoad (key also in data/share_schema.json town_system_keys).
## Remaining "household 1" assumptions (documented, safe for now): NewGame.start sets World.current_household_id = 1 and registers player 1 ->
## household 1; tests/hood_kit and start_kit create household 1; ScenarioGoals pays the primary household. Everything else asks Players.

const LOCAL := 1
const COLORS := [Color("#3d85c6"), Color("#e07a5f"), Color("#81b29a"), Color("#c77dbb")]     # name tag / ring colour per player id 1..4

## The player id of THIS machine: LOCAL (the host / a solo game) or, on a co-op client, the id the host gave us. UI and `primary_household()` follow it.
static var local_id: int = LOCAL
static var table: Dictionary = {}          # player id -> {"household_id": int, "name": String}

static func reset() -> void:
	table.clear()
	local_id = LOCAL

static func set_player(player_id: int, household_id: int, name: String = "") -> void:
	table[player_id] = {"household_id": household_id, "name": name if name != "" else "Player %d" % player_id}

static func remove_player(player_id: int) -> void:
	table.erase(player_id)

static func ids() -> Array:
	var out: Array = table.keys()
	out.sort()
	return out

static func count() -> int:
	return maxi(table.size(), 1)

## The household a player controls (-1 for an unknown player other than LOCAL).
static func household_of(player_id: int) -> int:
	if table.has(player_id):
		return int((table[player_id] as Dictionary)["household_id"])
	return _fallback_household() if player_id == LOCAL else -1

static func name_of(player_id: int) -> String:
	return str((table.get(player_id, {}) as Dictionary).get("name", "Player %d" % player_id))

## The player who controls a household (-1 = nobody: an NPC household).
static func player_of(household_id: int) -> int:
	for pid in ids():
		if int((table[pid] as Dictionary)["household_id"]) == household_id:
			return int(pid)
	if table.is_empty() and household_id == _fallback_household():
		return LOCAL
	return -1

static func owns(player_id: int, household_id: int) -> bool:
	return household_of(player_id) == household_id and household_id > 0

## The local player's household (what Economy.primary_household() answers).
static func primary_household() -> int:
	return household_of(local_id)

static func color_of(player_id: int) -> Color:
	return COLORS[clampi(player_id - 1, 0, COLORS.size() - 1)]

## A household id nobody uses yet (for a player joining a running town).
static func new_household_id() -> int:
	var top := 0
	for pid in ids():
		top = maxi(top, int((table[pid] as Dictionary)["household_id"]))
	for f in WorldIface.all_folk():
		top = maxi(top, int(f.household_id))
	return top + 1

static func _fallback_household() -> int:
	var w = WorldIface.world()
	if w != null and "current_household_id" in w and int(w.current_household_id) > 0:
		return int(w.current_household_id)
	var hs: Array = []
	for f in WorldIface.all_folk():
		if int(f.household_id) > 0 and not hs.has(int(f.household_id)):
			hs.append(int(f.household_id))
	hs.sort()
	return int(hs[0]) if not hs.is_empty() else 1

static func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for pid in ids():
		out[str(pid)] = (table[pid] as Dictionary).duplicate()
	return {"table": out}

static func from_dict(d: Dictionary) -> void:
	table.clear()
	var t: Dictionary = d.get("table", {})
	for k in t:
		table[int(k)] = {"household_id": int((t[k] as Dictionary).get("household_id", 1)), "name": str((t[k] as Dictionary).get("name", "Player %s" % k))}
