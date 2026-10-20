class_name SoloStart
extends RefCounted
## The last touches of a fresh solo game: the Easy start has a sofa bed in the flat, the first board of jobs always has openings a player can take
## without a computer, and the pawn begins awake with nothing queued. Numbers: data/solo.json "start".

static func finish(folk: Array) -> void:
	if folk.is_empty():
		return
	var hid: int = int(folk[0].household_id)
	if bool(SoloCfg.by_diff("start", "sofa_bed")):
		_place_sofa_bed(hid)
	SoloJobs.seed_board()

static func _place_sofa_bed(hid: int) -> void:
	var w = WorldIface.world()
	var rc: Rect2i = NeighborhoodLots.rect_of(Neighborhood.HOME)
	if w == null or rc.size.x <= 0:
		return
	var rooms: Array = AutoFurnish._rooms(w, rc)
	if rooms.is_empty():
		return
	for room in AutoFurnish._rooms_by_preference(rooms, "largest"):
		var oid: int = AutoFurnish._place_one(w, hid, "sofa_bed", room, rc, [])
		if oid >= 0:
			Economy.claim_bought(hid, oid, "sofa_bed", 0)          # a gift of the landlord: the first flat comes with a sofa bed on Easy
			return
