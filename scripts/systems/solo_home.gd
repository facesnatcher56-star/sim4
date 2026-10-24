class_name SoloHome
extends RefCounted
## Where the pawn lives (one-character play, docs/ONE_CHARACTER_PLAN.md R12): the tenancy on the ladder, the lockout after an eviction (homeless),
## the movers' store and the bookkeeping of lot roles. The lot named "home" is a ROLE: moving house swaps the role with another lot (SoloMove),
## so every system that asks for the home lot keeps working. Rent bills are the ordinary HousingRent bills; this class only adds the end states.
## Saved in the "solo" block of SaveLoad. Numbers: data/solo.json (SoloCfg).

static var active: bool = false           # a one-character game is running (NewGame sets it)
static var rung: String = "starter"       # ladder rung id of the pawn's present place ("street" = homeless)
static var homeless: bool = false         # evicted or left: locked out of the home role's lot
static var since_day: int = 1             # day the present tenancy began
static var notice_day: int = -1           # day the landlord's eviction notice was served (-1 none)
static var leaving_day: int = -1          # day the pawn gave notice (moves out then or earlier)
static var council_day: int = -1          # day the council list application was made (-1 none)
static var deposit: int = 0               # deposit held by the landlord
static var stored: Array = []             # belongings in store after a move or the movers: [{"def": id, "value": coins}]
static var shelter_week: int = 0          # week number for the shelter night count
static var shelter_nights: int = 0        # nights used this week
static var rough_nights: int = 0          # nights slept rough in a row (for the chronicle)
static var phys: Dictionary = {}          # lot id -> id of the lot physically standing there (after role swaps); empty = identity
static var arrears_block: bool = true     # unpaid bills block new rentals (the ladder checks Economy)

static func reset() -> void:
	active = false
	rung = "starter"
	homeless = false
	since_day = 1
	notice_day = -1
	leaving_day = -1
	council_day = -1
	deposit = 0
	stored = []
	shelter_week = 0
	shelter_nights = 0
	rough_nights = 0
	phys = {}
	SoloMove.reset()
	SoloPressure.reset()
	SoloGrey.reset()
	DailyHook.reset()
	SoloCrews.reset()
	SoloDistricts.reset()

static func is_homeless() -> bool:
	return active and homeless

## The pawn is locked out of the home lot (evicted); everybody else may still walk in.
static func locked_out(f) -> bool:
	return active and homeless and Pawn.is_pawn(f)

## Why these folk may not go to `lot_id` ("" = they may): the old home is locked after an eviction, the shelter is only for people with no home.
static func travel_refusal(folk_ids: Array, lot_id: String) -> String:
	if not active:
		return ""
	var pawn_in := false
	for id in folk_ids:
		if Pawn.is_pawn_id(int(id)):
			pawn_in = true
	if not pawn_in:
		return ""
	if lot_id == Neighborhood.HOME and homeless:
		return "You have no home to go to: the landlord has changed the locks."
	if lot_id == SoloShelter.lot_id() and not homeless:
		return "The shelter is for people with no home."
	return ""

## The label (lot id as the game knows it now) of the building that was originally called `orig`.
static func label_of_phys(orig: String) -> String:
	for id in phys:
		if str(phys[id]) == orig:
			return str(id)
	return orig

static func rung_def() -> Dictionary:
	return SoloCfg.rung(rung)

static func hid() -> int:
	return Economy.primary_household()

## The map-home property of the pawn's tenancy (the rent bills hang on it).
static func prop() -> Dictionary:
	return SoloMove.prop_at(Neighborhood.HOME)

static func to_dict() -> Dictionary:
	if not active:
		return {}
	return {"rung": rung, "homeless": homeless, "since": since_day, "notice": notice_day, "leaving": leaving_day, "council": council_day, "deposit": deposit,
		"stored": stored.duplicate(true), "sweek": shelter_week, "snights": shelter_nights, "rough": rough_nights, "phys": phys.duplicate(),
		"pressure": SoloPressure.to_dict(), "grey": SoloGrey.to_dict(), "hook": DailyHook.to_dict(), "districts": SoloDistricts.rough.duplicate(), "driveby": [SoloCrews.due_abs, SoloCrews.district_id]}

static func from_dict(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		return
	active = true
	rung = str(d.get("rung", "starter"))
	homeless = bool(d.get("homeless", false))
	since_day = int(d.get("since", 1))
	notice_day = int(d.get("notice", -1))
	leaving_day = int(d.get("leaving", -1))
	council_day = int(d.get("council", -1))
	deposit = int(d.get("deposit", 0))
	stored = (d.get("stored", []) as Array).duplicate(true)
	shelter_week = int(d.get("sweek", 0))
	shelter_nights = int(d.get("snights", 0))
	rough_nights = int(d.get("rough", 0))
	phys = (d.get("phys", {}) as Dictionary).duplicate()
	SoloPressure.from_dict(d.get("pressure", {}))
	SoloGrey.from_dict(d.get("grey", {}))
	DailyHook.from_dict(d.get("hook", {}))
	SoloDistricts.rough = (d.get("districts", {}) as Dictionary).duplicate()
	var db: Array = d.get("driveby", [-1, ""])
	SoloCrews.due_abs = int(db[0])
	SoloCrews.district_id = str(db[1])
	SoloMove.resync_positions()
