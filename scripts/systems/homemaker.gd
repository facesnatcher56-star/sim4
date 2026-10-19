class_name Homemaker
extends RefCounted
## "Stay at home": a role a household member can take instead of a career (a command, settable in the creator and on the folk panel).
## A homemaker gets no job offers, cannot be hired, and gives the household a small daily bonus (cleaner house, a tidied fridge, a little
## extra attention for the little ones). Autonomy also weighs chores, cooking and groceries higher for them (`mult`). Data: data/careers.json "homemaker".
## State: Careers.homemakers (saved with the careers block).

static func cfg() -> Dictionary:
	return Careers.cfg().get("homemaker", {})

static func is_homemaker(f) -> bool:
	return f != null and Careers.homemakers.has(int(f.id))

## Anyone who may hold a job can take the role (kids and teens cannot).
static func can_be(f) -> bool:
	return f != null and SysUtil.is_resident(f) and str(f.age_stage) in ["adult", "elder"] and int(f.household_id) > 0

## Command handler body. Returns true when something changed.
static func set_role(f, on: bool) -> bool:
	if f == null or is_homemaker(f) == on:
		return false
	var id: int = int(f.id)
	if on:
		if not can_be(f):
			return false
		if Careers.jobs.has(id):
			Careers.quit_job(f, "stay_at_home")
		Careers.offers.erase(id)
		Careers.seeking.erase(id)
		Careers.homemakers[id] = true
		SysUtil.notify("%s will stay at home and look after the house and the family." % f.name, "info")
	else:
		Careers.homemakers.erase(id)
		SysUtil.notify("%s is open to work again." % f.name, "info")
	SysUtil.game_event("homemaker_set", {"folk_id": id, "on": on})
	return true

## Autonomy weight of an interaction for this folk (1.0 for everybody else).
static func mult(folk, d: Dictionary) -> float:
	if not Careers.homemakers.has(int(folk.id)):
		return 1.0
	var tags: Array = d.get("tags", [])
	var best: float = 1.0
	var w: Dictionary = cfg().get("autonomy_mult", {})
	for t in w:
		if tags.has(t):
			best = maxf(best, float(w[t]))
	return best

## Once a day (Careers.on_day): the small household bonus from each homemaker who is home.
static func on_day() -> void:
	var c: Dictionary = cfg()
	for fid in Careers.homemakers.keys():
		var f = SysUtil.folk(int(fid))
		if f == null or not SysUtil.is_resident(f) or SysUtil.is_away(f):
			continue
		var hid: int = int(f.household_id)
		for o in Economy.objects_of(hid):
			var dirt: float = float(WorldIface.state_get(o, "dirtiness", 0.0))
			if dirt > 0.0:
				WorldIface.state_add(o, "dirtiness", -float(c.get("clean_per_day", 1.0)))
			if str(o.def_id) == "fridge" and float(WorldIface.state_get(o, "spoiled", 0.0)) > 0.0:
				WorldIface.state_set(o, "spoiled", 0.0)
		for k in SysUtil.residents():
			if int(k.household_id) == hid and str(k.age_stage) in ["baby", "toddler", "child"]:
				for n in (c.get("kid_bonus", {}) as Dictionary):
					k.add_to_stat(str(n), float(c["kid_bonus"][n]))
