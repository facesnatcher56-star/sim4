class_name PhoneDay
extends RefCounted
## The daily part of the phone (task 14): friends who are townies text residents to go out ("Mina texted: fancy the cinema?"). A resident of teen age or
## older gets at most one a day, with chance `incoming_per_day`, from a friend (friendship >= `incoming_min_friendship`) who is free to come, for an
## outing both can do. The invitation waits `invite_days` days in the phone's inbox (PhoneState) and is answered with PhoneCmd.respond.
## Tier: residents only (ACTIVE), one dice each per day.

static func on_day(day: int) -> void:
	PhoneState.on_day(day)
	PhoneOwn.on_day(day)
	var pc: Dictionary = PhoneState.cfg()
	var p: float = float(pc.get("incoming_per_day", 0.25))
	for f in SysUtil.residents():
		var fid: int = int(f.id)
		if str(f.age_stage) in ["baby", "toddler", "child"] or SysUtil.is_away(f):
			continue
		if PhoneState.rng.randf() >= p or PhoneState.inbox_of(fid).size() >= int(pc.get("inbox_cap", 6)):
			continue
		_one(f, fid)

static func _one(f, fid: int) -> void:
	if PhoneOwn.block(fid) != "":
		return          # no working phone: nobody can text the pawn
	var min_fr: float = float(PhoneState.cfg().get("incoming_min_friendship", 25.0))
	var friends: Array = PhoneCmd.contacts(fid, 30).filter(func(c): return bool(c["townie"]) and float(c["friendship"]) >= min_fr and str(c["reason"]) == "" and EduState.stage_of(int(c["id"])) in ["teen", "adult", "elder"])
	if friends.is_empty():
		return
	var weights: Array = friends.map(func(c): return float(c["friendship"]))
	var pick = SysUtil.pick_weighted(friends, weights)
	if pick == null:
		return
	var who: int = int(pick["id"])
	var options: Array = LifeOuting.outings().filter(func(o): return LifeOuting.could(fid, who, o))
	if options.is_empty():
		return
	var o: Dictionary = options[PhoneState.rng.randi_range(0, options.size() - 1)]
	var text: String = "%s texted: fancy %s?" % [SysUtil.folk_name(who), str(o.get("label", "going out"))]
	PhoneState.add_invite(fid, who, "", str(o["id"]), text)
	SysUtil.notify(text + " (Phone)", "info")
