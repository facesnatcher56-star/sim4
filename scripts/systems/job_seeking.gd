class_name JobSeeking
extends RefCounted
## Who may take a job offer on their own: only somebody actually looking for work - jobless, not a homemaker, and either searching
## (the 'Look for Jobs' interaction) or short of money - and not right after they last changed jobs. Everyone else lets the offer wait
## (it expires after a few days). Data: data/careers.json "seeking".

static func cfg() -> Dictionary:
	return Careers.cfg().get("seeking", {})

## Does the household own a computer (or a job terminal) to look for work at? Without one the only routes are the Town -> Jobs tab and asking around.
static func has_computer(hid: int) -> bool:
	for o in Economy.objects_of(hid):
		if str(o.def_id) in ["computer", "terminal"]:
			return true
	return false

## How to answer a job offer, for the offer toast: names the route the household really has (task 33c).
static func accept_hint(f) -> String:
	if f != null and not has_computer(int(f.household_id)):
		return "Click Town, open the Jobs tab and apply there (or accept it in the Work window)."
	return "Use a computer's 'Look for Jobs' to accept (or accept it in the Work window)."

static func is_seeking(f) -> bool:
	if f == null or Careers.jobs.has(int(f.id)) or Careers.retired.has(int(f.id)) or Careers.homemakers.has(int(f.id)):
		return false
	var c: Dictionary = cfg()
	var fid: int = int(f.id)
	if Careers.seeking.has(fid) and SysUtil.day() - int(Careers.seeking[fid]) <= int(c.get("search_days", 3)):
		return true
	if bool(c.get("no_computer_looks", true)) and not has_computer(int(f.household_id)):
		return true             # jobless and no computer to search from: they ask around town and take what they are offered (cause: they need work; the offer expires if nobody answers)
	return Economy.balance(int(f.household_id)) < int(c.get("broke_below", 300))

static func cooled_down(f) -> bool:
	var last: int = int(Careers.changed_day.get(int(f.id), -999))
	return SysUtil.day() - last >= int(cfg().get("min_days_between_changes", 7))

static func may_take(f) -> bool:
	return is_seeking(f) and cooled_down(f)
