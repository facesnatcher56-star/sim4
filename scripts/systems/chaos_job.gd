class_name ChaosJob
extends RefCounted
## Work-life trouble (task 07b), adults only. Numbers: config.chaos.life.
##  - layoff: cutbacks at the workplace (rumours first, a day ahead; doing well at work, or being senior, protects) take the job and pay a week of
##    severance. Rarely it is a closure: everybody in the household with the same kind of job goes. The person can look for a new job at once.
##    Far townies lose their career and start looking (the town's own job dice find them a new one).
##  - midlife crisis: adults in their middle years get restless. A burnt-out workaholic, a sudden quit, a pricey splurge, or just a rough week.

static func cfg() -> Dictionary:
	return ChaosState.cfg("life")

static func layoff(ctx: Dictionary, args: Dictionary) -> Dictionary:
	if bool(ctx.get("statistical", false)):
		var t: Dictionary = ctx["subject"].t()
		if not t.is_empty() and str(t.get("career", "")) != "":
			t["career"] = ""
			t["level"] = 1
			t["seeking"] = true
		return {}
	var f = ctx.get("folk", null)
	if f == null or not Careers.has_job(int(f.id)):
		return {"text": ""}
	var closure: bool = str(args.get("how", "cut")) == "closure"
	var cid: String = Careers.career_of(int(f.id))
	var gone: Array = [f]
	if closure:
		for o in SysUtil.residents():
			if int(o.household_id) == int(f.household_id) and int(o.id) != int(f.id) and Careers.career_of(int(o.id)) == cid:
				gone.append(o)
	var label: String = str(Careers.career_def(cid).get("label", "work")).to_lower()
	var pay := 0
	for p in gone:
		var lv: Dictionary = Careers.level_def(Careers.career_of(int(p.id)), Careers.level_of(int(p.id)), Careers.branch_of(int(p.id)))
		pay += int(float(lv.get("pay", 10)) * float(cfg().get("severance_hours", 40)))
		Careers.quit_job(p, "laid_off")
		p.add_buff("laid_off")
	if pay > 0:
		Economy.deposit(int(f.household_id), pay, "severance pay")
	ChaosState.count("closure" if closure else "layoff")
	if closure:
		var who: String = "%s is" % f.name if gone.size() == 1 else "%s and %d more are" % [f.name, gone.size() - 1]
		return {"text": "The %s business closed down. %s out of work, with %d coins of severance. Check the job board for something new." % [label, who, pay], "kind": "bad"}
	return {"text": "%s was laid off in cutbacks at the %s job, with %d coins of severance. Check the job board for something new." % [f.name, label, pay], "kind": "bad"}

static func midlife(ctx: Dictionary, args: Dictionary) -> Dictionary:
	if bool(ctx.get("statistical", false)):
		return {}
	var f = ctx.get("folk", null)
	if f == null:
		return {"text": ""}
	var c: Dictionary = cfg()
	ChaosState.count("midlife")
	match str(args.get("how", "restless")):
		"burnout":
			f.add_buff("burnt_out")
			return {"text": "%s is burnt out after years of putting work first. A few slow days, some fun and some sleep would help." % f.name, "kind": "warn"}
		"quit":
			if Careers.has_job(int(f.id)):
				Careers.quit_job(f, "midlife")
				f.add_buff("midlife_crisis")
				return {"text": "%s woke up one morning, decided that was enough, and quit the job. A midlife crisis, the housemates say." % f.name, "kind": "warn"}
		"splurge":
			var cost: int = Incidents.rng.randi_range(int((c.get("splurge", [120, 300]) as Array)[0]), int((c.get("splurge", [120, 300]) as Array)[1]))
			cost = mini(cost, maxi(Economy.balance(int(f.household_id)) / 3, 0))
			if cost > 0 and Economy.spend(int(f.household_id), cost, "midlife splurge"):
				f.add_buff("midlife_crisis")
				f.add_to_stat("fun", 30.0)
				return {"text": "%s spent %d coins on something shiny and completely impractical. A midlife crisis, the housemates say." % [f.name, cost], "kind": "warn"}
	f.add_buff("midlife_crisis")
	return {"text": "%s is restless and keeps asking what it was all for. A midlife crisis: a hobby, a friend or a good night's sleep might help." % f.name, "kind": "warn"}
