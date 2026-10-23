class_name Upkeep
extends RefCounted
## What a household's home costs each week and when the next payments come, from the same numbers that charge them: the rent (HousingRent,
## issued every `pay_days`, due 3 days later) and the household bills (Economy: water, power, phone; their size is the live estimate). The money
## window, the Homes tab and the holiday planner all show these, so they never disagree.

## [{what, amount, day}] of the payments still to come, soonest first (already issued and unpaid bills are not here: Economy.outstanding).
static func upcoming(hid: int) -> Array:
	var out: Array = []
	var rent: int = weekly_rent(hid)
	if rent > 0:
		var issue: int = HousingRent.next_cycle if HousingRent.next_cycle > 0 else SysUtil.day() + HousingRent.pay_days()
		out.append({"what": "Rent", "amount": rent, "day": issue + 3})
	if not SoloHome.is_homeless():
		var day: int = Economy.next_bill_day if Economy.next_bill_day > 0 else int(Economy.bill_cfg().get("first_day", 7))
		out.append({"what": "Household bills", "amount": Economy.compute_bill(hid), "day": day + int(Economy.bill_cfg().get("due_after_days", 3))})
	out.sort_custom(func(a, b): return int(a["day"]) < int(b["day"]))
	return out


## The household's weekly rent (0 for owners, the homeless and households that are not tenants).
static func weekly_rent(hid: int) -> int:
	for p in HousingProps.props.values():
		if str(p.get("tenant_kind", "")) == "player" and int(p.get("tenant", -1)) == hid:
			return int(p.get("rent", 0))
	return 0


## Rent plus bills a week.
static func weekly(hid: int) -> int:
	return weekly_rent(hid) + (0 if SoloHome.is_homeless() else Economy.compute_bill(hid))


## What has to stay in the bank for `days` from today: the unpaid bills plus every payment that falls due in that time.
static func needed_for(hid: int, days: int) -> int:
	var n: int = Economy.owed(hid)
	var last: int = SysUtil.day() + days
	for u in upcoming(hid):
		var d: int = int(u["day"])
		while d <= last:
			n += int(u["amount"])
			d += 7
	return n
