class_name ChaosNeglect
extends RefCounted
## Neglect and child services (task 07b). Uses the EXISTING child services path (ChildServices, task 20): a report, a home visit the next
## day, a safety plan or, when it happens again, a placement with a relative or foster family. This file adds no new harm content: it only decides
## WHEN a neglected toddler or child is reported, from needs the health system already tracks (Health: hunger, hygiene or energy under -60 for
## eight hours gives the `neglected` buff and calls `on_neglect` below).
##  - First the player is told, in plain words, that child services may step in (toast from `on_neglect`).
##  - Each day the child is still `neglected` and no grown-up is looking after them right now adds a day to ChaosState.neglect (a good day takes
##    one off). After `days_to_report` days a teacher (children) or a neighbour (toddlers) raises concerns: ChildServices.report.
##  - A visit that finds nothing wrong closes the file; a second referral for the same child counts as a repeat and ChildServices places them.
## Elders who cannot look after themselves keep only the health task's warning and moods (not covered here). Far children: not simulated.

static func cfg() -> Dictionary:
	return ChaosState.cfg("neglect")

static func _minor(f) -> bool:
	return str(f.age_stage) in ["toddler", "child"]

## Health.register_neglect_hook callback (once, when the neglect meter first warns).
static func on_neglect(f, _info: Dictionary) -> void:
	if f == null or not SysUtil.is_resident(f) or not _minor(f):
		return
	SysUtil.notify("%s has gone without food, a wash or sleep for far too long. If nobody steps in, child services may be told." % f.name, "warn")

## Is a grown-up of the household looking after this child at this moment?
static func adult_acting(child) -> bool:
	for o in SysUtil.residents():
		if int(o.household_id) != int(child.household_id) or not (str(o.age_stage) in ["adult", "elder"]) or SysUtil.is_away(o):
			continue
		if o.current != null and int(o.current.target_id) == int(child.id):
			return true
	return false

static func on_day() -> void:
	if ChaosState.neglect.is_empty() and not _any_neglected() and ChildServices.kids().is_empty():
		return
	var c: Dictionary = cfg()
	for f in SysUtil.residents():
		if not _minor(f):
			continue
		var id: int = int(f.id)
		if f.has_buff("neglected") and not adult_acting(f):
			ChaosState.neglect[id] = int(ChaosState.neglect.get(id, 0)) + 1
			if int(ChaosState.neglect[id]) >= int(c.get("days_to_report", 2)):
				refer(f)
		elif ChaosState.neglect.has(id):
			var left: int = int(ChaosState.neglect[id]) - 1
			if left > 0:
				ChaosState.neglect[id] = left
			else:
				ChaosState.neglect.erase(id)
	_visit_news()

static func _any_neglected() -> bool:
	for f in SysUtil.residents():
		if f.has_buff("neglected"):
			return true
	return false

## Raise concerns with child services through the existing path.
static func refer(f) -> void:
	var id: int = int(f.id)
	ChaosState.neglect.erase(id)
	var kid: Dictionary = ChildServices.kids().get(id, {"incidents": 0, "trauma": 0.0, "reported": false, "case": -1, "serious": false})
	if not (kid.get("placed", {}) as Dictionary).is_empty() or (bool(kid.get("reported", false)) and not bool(kid.get("visited", false))):
		return                                             # already placed, or a visit is already on its way
	var carers: Array = CrimeChildAbuse.carers_of(id)
	kid["carer"] = int(carers[0]) if not carers.is_empty() else -1
	kid["incidents"] = int(kid["incidents"]) + 1
	kid["last_day"] = SysUtil.day()
	kid["neglect"] = true
	kid["neglect_told"] = false
	kid["reported"] = false
	kid["visited"] = false
	ChildServices.kids()[id] = kid
	ChaosState.count("neglect_report")
	ChildServices.report(id, "teacher" if str(f.age_stage) == "child" else "neighbour")

## The visit itself is chronicled by ChildServices, which also tells the player about a safety plan or a placement. A visit that found nothing
## is silent there, so say it here, once.
static func _visit_news() -> void:
	for id in ChildServices.kids().keys():
		var kid: Dictionary = ChildServices.kids()[id]
		if not bool(kid.get("neglect", false)) or bool(kid.get("neglect_told", false)) or not bool(kid.get("visited", false)):
			continue
		kid["neglect_told"] = true
		var f = SysUtil.folk(int(id))
		if (kid.get("placed", {}) as Dictionary).is_empty() and not bool(kid.get("reported", false)) and f != null and SysUtil.is_resident(f):
			var nm: String = CrimePerson.name_of(int(id))
			SysUtil.notify("A social worker looked at the food, the cleanliness and who was home for %s and found nothing to act on this time. Keep %s fed, clean and rested." % [nm, nm], "info")
