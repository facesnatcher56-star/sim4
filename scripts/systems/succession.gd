class_name Succession
extends RefCounted
## The player's role and heir succession (task 15). The player controls ONE household (per player id, via the Players table) and one of its members
## is its HEAD. When the head dies, control passes along the heir line (HeirLine): spouse / partner -> grown children (even moved out) -> the other
## children -> siblings -> housemates -> other relatives. Whoever lives elsewhere MOVES BACK INTO THE FAMILY HOME (the household id, funds and furniture
## stay), so a moved-out child is never controlled until this moment. If nobody can take over, SuccessionNobody asks the player (autopilot meanwhile).
## Never decides anything on its own clock: it is called by Aging.kill (begin / finish) and by the day row (pending households). State lives in the
## Players table (head, heir, pending ...), so it saves, resets and replays with it. Commands: set_heir, choose_successor (SuccessionCmd).

## The head of the household of `player_id`: the stored one while they are alive and live there, else the eldest-created grown-up (and it is stored).
static func head_of(player_id: int) -> int:
	var hid: int = Players.household_of(player_id)
	if hid <= 0:
		return -1
	var h: int = int(Players.field(player_id, "head", -1))
	var f = SysUtil.folk(h) if h >= 0 else null
	if f != null and SysUtil.is_resident(f) and int(f.household_id) == hid:
		return h
	var d: int = default_head(hid)
	if d >= 0:
		_ensure_entry(player_id)
		Players.set_field(player_id, "head", d)
	return d

static func default_head(household_id: int) -> int:
	var best: int = -1
	var best_any: int = -1
	for f in SysUtil.residents():
		if int(f.household_id) != household_id:
			continue
		var id: int = int(f.id)
		if best_any < 0 or id < best_any:
			best_any = id
		if str(f.age_stage) in ["adult", "elder"] and (best < 0 or id < best):
			best = id
	return best if best >= 0 else best_any

static func set_head(player_id: int, folk_id: int) -> void:
	_ensure_entry(player_id)
	Players.set_field(player_id, "head", folk_id)
	Players.set_field(player_id, "heir", -1)

## An empty players table means nobody plays (an NPC-driven household, the reviewer's probes): do not bring a player back by naming a head.
static func _ensure_entry(player_id: int) -> void:
	if Players.table.is_empty():
		return
	if not Players.table.has(player_id) and Players.household_of(player_id) > 0:
		Players.set_player(player_id, Players.household_of(player_id), "Player" if player_id != Players.LOCAL else "")

static func is_pending(player_id: int) -> bool:
	return bool(Players.field(player_id, "pending", false))

# ------------------------------------------------------------------ the player's pick
## The heir the player picked, or -1.
static func heir_of(player_id: int) -> int:
	var h: int = int(Players.field(player_id, "heir", -1))
	return h if h >= 0 and HeirLine.eligible(h, Players.household_of(player_id), player_id) else -1

## Pick the heir (family panel). Must be somebody who would be in the line (family or housemate); -1 clears the pick.
static func pick_heir(player_id: int, heir_id: int) -> Dictionary:
	var hid: int = Players.household_of(player_id)
	if hid <= 0:
		return {"ok": false, "msg": "You do not play a household."}
	_ensure_entry(player_id)
	if heir_id < 0:
		Players.set_field(player_id, "heir", -1)
		return {"ok": true, "msg": "Nobody is picked: the family line decides."}
	var head: int = head_of(player_id)
	if heir_id == head:
		return {"ok": false, "msg": "The head cannot be their own heir."}
	var found: bool = false
	var old: int = int(Players.field(player_id, "heir", -1))
	Players.set_field(player_id, "heir", -1)
	for c in HeirLine.candidates(head, hid, player_id):
		if int(c["id"]) == heir_id:
			found = true
	if not found:
		Players.set_field(player_id, "heir", old)
		return {"ok": false, "msg": "Only family or people in your house can be the heir."}
	Players.set_field(player_id, "heir", heir_id)
	return {"ok": true, "msg": "%s will play on when the head of the family dies." % Family.name_of(heir_id)}

# ------------------------------------------------------------------ a death
## Called by Aging.kill BEFORE the death is processed (the spouse link is still there). Returns a plan for `finish`, or {} when the dead person is
## not the head of a player's household.
static func begin(folk_id: int) -> Dictionary:
	var f = SysUtil.folk(folk_id)
	if f == null or not SysUtil.is_resident(f):
		return {}
	var hid: int = int(f.household_id)
	var pid: int = Players.player_of(hid)
	if pid < 0:
		return {}
	if head_of(pid) != folk_id:
		if int(Players.field(pid, "heir", -1)) == folk_id:
			Players.set_field(pid, "heir", -1)           # the picked heir died: the line decides again
		return {}
	LifeSummary.on_pawn_death(folk_id, str(f.name))          # task 44: what the life was, why, and what it set in motion
	return {"pid": pid, "hid": hid, "head": folk_id, "name": str(f.name), "line": HeirLine.candidates(folk_id, hid, pid)}

## Called by Aging.kill after the head has left the world.
static func finish(plan: Dictionary) -> void:
	if plan.is_empty():
		return
	var pid: int = int(plan["pid"])
	var hid: int = int(plan["hid"])
	var line: Array = plan["line"]
	var mates: int = 0
	for f in SysUtil.residents():
		if int(f.household_id) == hid:
			mates += 1
	Players.set_field(pid, "gone", int(plan["head"]))
	if line.is_empty() or (mates == 0 and int(line[0]["rank"]) >= 6):     # nobody, or only far relatives and an empty house: the player chooses
		SuccessionNobody.begin(pid, hid, str(plan["name"]), line)
		return
	SuccessionTake.take(pid, hid, line[0], str(plan["name"]))

# ------------------------------------------------------------------ day row
## Daily (SimRegistry): households waiting for the player's choice.
static func on_day(day: int) -> void:
	for pid in Players.ids():
		if is_pending(int(pid)):
			SuccessionNobody.on_day(int(pid), day)

## True while a player's household has nobody in it (never true for long: the day row settles it).
static func empty_household(player_id: int) -> bool:
	var hid: int = Players.household_of(player_id)
	if hid <= 0:
		return false
	for f in SysUtil.residents():
		if int(f.household_id) == hid:
			return false
	return true
