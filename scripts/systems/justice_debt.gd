class_name JusticeDebt
extends RefCounted
## Court debt (34 logic): a fine or restitution that cannot be paid at once does not vanish. It is COURT DEBT: every day a share of what the person has
## is taken as an instalment (a payment plan from income); restitution goes to the victim (a civil claim), fines to the court. Instalments missed on
## `miss_days` days in a row cost community service, and again and again, a few days in jail. Debt blocks renting (a debtor has unpaid bills as far as the
## housing ladder is concerned) and is shown in the money view. Numbers: data/justice.json "debt".

static func cfg() -> Dictionary:
	return JusticeState.sect("debt")

static func _entry(pid: int) -> Dictionary:
	if not JusticeState.debts.has(pid):
		JusticeState.debts[pid] = {"fine": 0, "rest": {}, "missed": 0}
	return JusticeState.debts[pid]

static func add_fine(pid: int, n: int) -> void:
	if n > 0:
		var e: Dictionary = _entry(pid)
		e["fine"] = int(e["fine"]) + n

static func add_restitution(pid: int, victim: int, n: int) -> void:
	if n > 0:
		var e: Dictionary = _entry(pid)
		var r: Dictionary = e["rest"]
		r[victim] = int(r.get(victim, 0)) + n

static func owed(pid: int) -> int:
	var e: Dictionary = JusticeState.debts.get(pid, {})
	var t: int = int(e.get("fine", 0))
	for v in (e.get("rest", {}) as Dictionary):
		t += int(e["rest"][v])
	return t

static func on_day() -> void:
	var c: Dictionary = cfg()
	if SysUtil.day() % int(c.get("every_days", 7)) != 0:
		return          # weekly instalments only
	for pid in JusticeState.debts.keys():
		var e: Dictionary = JusticeState.debts[pid]
		if owed(int(pid)) <= 0 or not CrimePerson.alive(int(pid)):
			JusticeState.debts.erase(pid)
			continue
		if CrimePerson.in_custody(int(pid)):
			continue
		var have: int = CrimePerson.coins(int(pid))
		var spare: int = have - int(c.get("floor", 60))          # never the food money: only what is above the subsistence floor counts as income
		var inst: int = mini(maxi(int(float(spare) * float(c.get("share", 0.5))), 0), owed(int(pid)))
		if inst <= 0:
			e["missed"] = int(e["missed"]) + 1
			_penalty(int(pid), e, c)
			continue
		e["missed"] = 0
		var left: int = CrimePerson.pay(int(pid), inst, "court debt")
		for v in (e["rest"] as Dictionary).keys():
			if left <= 0:
				break
			var part: int = mini(left, int(e["rest"][v]))
			CrimePerson.add_coins(int(v), part, "restitution")
			e["rest"][v] = int(e["rest"][v]) - part
			left -= part
			if int(e["rest"][v]) <= 0:
				(e["rest"] as Dictionary).erase(v)
		if left > 0:
			e["fine"] = maxi(int(e["fine"]) - left, 0)
		if owed(int(pid)) <= 0:
			JusticeState.debts.erase(pid)
			if CrimePerson.is_player(int(pid)):
				SysUtil.notify("Your court debt is paid off.", "good")

static func _penalty(pid: int, e: Dictionary, c: Dictionary) -> void:
	var m: int = int(e["missed"])
	if m < int(c.get("miss_weeks", 2)) or m % int(c.get("miss_weeks", 2)) != 0:
		return          # no income: community service instead of taking the last coins
	if JusticeState.service.has(pid) or JusticeState.inmates.has(pid):
		return
	if m >= 3 * int(c.get("miss_weeks", 2)):
		JusticeState.service[pid] = {"days_left": int(c.get("service_days", 3)) * 2, "last_day": -1}
	else:
		JusticeState.service[pid] = {"days_left": int(c.get("service_days", 3)), "last_day": -1}
	if CrimePerson.is_player(pid):
		SysUtil.notify("Court debt unpaid for %d weeks: the court orders community service." % m, "warn")
