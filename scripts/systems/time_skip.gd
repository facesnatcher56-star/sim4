class_name TimeSkip
extends RefCounted
## One-character play, S4 (docs/ONE_CHARACTER_PLAN.md R8.2): at the top speed the clock races ahead while the pawn is doing something long that needs nobody
## (asleep, away at work or school, on a long walk) and drops back to the player's speed the moment anything needs the player. It predicts nothing and
## warns of nothing: it only stops on what is actually happening.
##   TimeSkip.rate() -> game minutes per real second to use now (0 = no skip); TimeSkip.reason() -> why it is skipping or why not (for the banner).
## Clock._process asks `rate()` each frame at speed 3 and advances at most MAX_PER_FRAME minutes a frame, so one slow frame never swallows a quarter hour:
## the margin before anything can happen is at least two frames of minutes.
## Stops: the pawn idle, a need near the floor, somebody at the door (a visitor on the lot), a prompt waiting, a fire or an intruder, a hospital stay.

const RATE := 60.0               # game minutes per real second while skipping
const MAX_PER_FRAME := 6         # the frame batch (also the margin: stop checks run every frame)
const NEED_STOP := -55.0         # a vital need this low stops the skip
const VITAL := ["hunger", "energy", "bladder", "hygiene"]
const STOP_BUFFS := ["intruder", "on_fire", "burning", "panic", "intruder_in_house"]

static var enabled: bool = true
static var active: bool = false          # skipping right now (the banner reads it)
static var why: String = ""

static func rate() -> float:
	var r: String = _blocker()
	active = (r == "")
	return RATE if active else 0.0

static func reason() -> String:
	return why

## "" = skip allowed; else why not.
static func _blocker() -> String:
	why = ""
	if not enabled or not SoloHome.active or Players.table.is_empty():
		return "off"
	var f = SysUtil.folk(Pawn.of())
	if f == null:
		return "no pawn"
	var doing: String = _doing(f)
	if doing == "":
		return "idle"
	for n in VITAL:
		if f.needs.has(n) and f.get_stat_value(n) < NEED_STOP and not (n == "energy" and doing == "asleep"):
			return "need"
	if JusticePlayer.log.size() > 0 and bool((JusticePlayer.log[JusticePlayer.log.size() - 1] as Dictionary).get("choice", "x") == ""):
		return "prompt"
	if Players.field(Players.local_id, "pending", false):
		return "nobody left"
	for b in STOP_BUFFS:
		if f.has_buff(b):
			return "danger"
	if _visitor_at_door(f):
		return "visitor"
	why = doing
	return ""

## What the pawn is doing that is safe to race through: "asleep", "away" (work, school, errands), "walking" (a long walk), or "" (not skippable).
static func _doing(f) -> String:
	if Away.is_away(int(f.id)):
		var reason: String = str(Away.info(int(f.id)).get("reason", ""))
		return "" if reason in ["hospital"] else "away"
	if f.current == null:
		return ""
	var tags: Array = f.current.def.get("tags", [])
	if tags.has("sleep"):
		return "asleep"
	if f.current.def_id == "go_here" and f.current.state == "walking":
		return "walking"
	return ""

## A visitor or a townie stands on the pawn's lot (somebody arrived: that wants the player).
static func _visitor_at_door(f) -> bool:
	var lot: String = NeighborhoodLots.lot_at(f.tile)
	if lot == "":
		return false
	for o in WorldIface.all_folk():
		if int(o.id) != int(f.id) and int(o.household_id) != int(f.household_id) and o.has_meta("visitor") and NeighborhoodLots.lot_at(o.tile) == lot:
			return true
	return false
