class_name AccidentOutcome
extends RefCounted
## The one handler behind every FULL accident outcome ("accident_outcome" in data/incidents/05_accidents.json).
## args: {severity 1..3 (0 = unhurt), reason, cause (id for the health system), kill "death cause id", buff "shaken_up"}.
## It hurts through Health.injure(folk, severity, reason) (task 02; severity 2+ goes to hospital); kills through Aging.kill;
## adds the shaken-up mood; and emits `accident_on_property` {victim, lot, owner, cause} when the victim was hurt on SOMEONE ELSE'S
## lot (a visitor on a household lot) so the lawsuit system (tasks 04 / 09) can hook it.

static func on_incident(ctx: Dictionary, args: Dictionary) -> Dictionary:
	if bool(ctx.get("statistical", false)):
		return {}
	var f = ctx.get("folk", null)
	if f == null:
		return {}
	var cause: String = str(args.get("cause", args.get("reason", "")))
	if str(args.get("kill", "")) != "":
		note_property(f, cause, true)
		Aging.kill(int(f.id), str(args["kill"]))
		return {}
	if int(args.get("severity", 0)) > 0:
		hurt(f, int(args["severity"]), str(args.get("reason", "")), cause)
		note_property(f, cause, false)
	if str(args.get("buff", "")) != "":
		f.add_buff(str(args["buff"]))
	return {}

static func hurt(f, severity: int, reason: String, _cause: String = "") -> void:
	Health.injure(f, severity, reason)

## Household that owns the lot the victim is hurt on, when it is not the victim's own (0 = none).
static func property_owner(f) -> int:
	for o in WorldIface.folk_near(f):
		if int(o.id) != int(f.id) and int(o.household_id) > 0 and int(o.household_id) != int(f.household_id):
			return int(o.household_id)
	return 0

static func note_property(f, cause: String, fatal: bool) -> void:
	var owner: int = property_owner(f)
	if owner > 0:
		SysUtil.game_event("accident_on_property", {"victim": int(f.id), "lot": "home:%d" % owner, "owner": owner, "cause": cause, "fatal": fatal})
