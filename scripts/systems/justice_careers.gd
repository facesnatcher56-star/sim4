class_name JusticeCareers
extends RefCounted
## Police officer, detective, lawyer and judge. The career definitions live in data/justice.json ("careers", the same shape as data/careers.json)
## and are merged into the careers table at install time. Townies fill these roles too (staff_town keeps a few posts filled so the town
## always has police, a lawyer and a judge). Daily tasks are tied to real cases: the interaction `work_case_file` (at a desk or computer)
## fires the game event `work_case`:
##   detective / officer: works on an open case (CaseInvestigation.assist) - a player detective can actually solve the town's cases
##   lawyer:              prepares the defence of the oldest case waiting for trial (better lawyer skill)
##   judge:               reviews a pending trial (fewer wrongful convictions)
## A criminal record keeps some jobs closed (Prison.job_ok), hooked into Careers.qualify.

const ROLES := ["police_officer", "detective", "lawyer", "judge"]

static func install() -> void:
	var table: Dictionary = Careers.cfg()
	if table.is_empty():
		return
	var careers: Dictionary = table.get("careers", {})
	for cid in (JusticeState.sect("careers") as Dictionary):
		if not careers.has(cid):
			careers[cid] = (JusticeState.sect("careers")[cid] as Dictionary).duplicate(true)

## Keep one post of each role filled among the townies (adults, no record, not elders).
static func staff_town() -> void:
	var tids: Array = CrimePerson.townies_only().filter(func(p): return CrimePerson.folk(p) == null and CrimePerson.stage(p) == "adult")
	if tids.size() < int(JusticeState.sect("general").get("staff_min_pop", 7)):
		return
	var want: Dictionary = {"police_officer": 1, "detective": 1, "lawyer": 1, "judge": 1}
	for tid in tids:
		var cr: String = CrimePerson.career(tid)
		if want.has(cr) and int(want[cr]) > 0:
			want[cr] = int(want[cr]) - 1
	for role in ROLES:
		while int(want[role]) > 0:
			var pick: int = -1
			var best: float = -1.0
			for tid in tids:
				if CrimePerson.has_job(tid) and CrimePerson.career(tid) not in ["cook", "coder", "painter", "fitness_coach"]:
					continue
				if CrimePerson.has_record(tid) or CrimePerson.in_custody(tid):
					continue
				var w: float = JusticeState.rng.randf() + (0.5 if not CrimePerson.has_job(tid) else 0.0) + (0.4 if (role == "judge" and CrimePerson.has_trait(tid, "honest")) else 0.0) \
					+ (0.4 if (role == "detective" and CrimePerson.has_trait(tid, "bookworm")) else 0.0) + (0.4 if (role == "lawyer" and CrimePerson.has_trait(tid, "charmer")) else 0.0)
				if w > best:
					best = w
					pick = int(tid)
			if pick < 0:
				break
			Story.townies[pick]["career"] = role
			Story.townies[pick]["level"] = 2 if role in ["judge", "detective"] else 1
			want[role] = int(want[role]) - 1
			tids.erase(pick)

## Careers.qualify hook: extra missing requirement text for a closed door.
static func extra_missing(pid: int, career: String) -> Array:
	if Prison.job_ok(pid, career):
		return []
	return ["a clean record"]

# ------------------------------------------------------------------ daily work
## Game event `work_case` {folk_id}: the folk's career decides what the work does.
static func on_work_case(folk_id: int) -> void:
	var cr: String = CrimePerson.career(folk_id)
	match cr:
		"detective", "police_officer":
			for c in CaseStore.in_state(["open", "cold"]):
				if int(c["victim"]) == folk_id:
					continue
				CaseInvestigation.assist(int(c["id"]))
				if str(c["state"]) == "cold":
					CaseInvestigation.reopen(c, "A detective took a fresh look.")
				if CrimePerson.is_player(folk_id):
					SysUtil.notify("Worked the case: %s." % CaseStore.title(c), "info")
				return
		"lawyer":
			for c in CaseStore.in_state(["charged"]):
				if int(c["accused"]) != folk_id:
					c["lawyer_skill"] = minf(float(c.get("lawyer_skill", 0.3)) + 0.05, 0.95)
					return
		"judge":
			for c in CaseStore.in_state(["charged"]):
				c["reviewed"] = true
				return

## Townie professionals do their job statistically every day.
static func on_day() -> void:
	staff_town()
	for pid in CrimePerson.townies_only():
		var cr: String = CrimePerson.career(pid)
		if cr in ["detective", "police_officer"] and JusticeState.chance(0.5):
			var open: Array = CaseStore.in_state(["open"])
			if not open.is_empty():
				CaseInvestigation.assist(int(open[0]["id"]))
