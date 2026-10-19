class_name CityAmbulance
extends RefCounted
## The ambulance (task 12.3): a serious injury or collapse at home is not a blink away from a hospital bed any more. Hospital.admit hands the call here; an ambulance
## starts from the hospital lot (CityServices.dispatch), the patient waits for the response minutes, and a slow response (longer than ambulance.worsen_after) can make
## the condition worse. Residents on the real map only: townies in a far house are statistical (CityServices.death_mult), and test worlds without a map admit at once.
##   CityAmbulance.hold(folk_id, severity, reason) -> true when the admission is now scheduled (the caller must not admit again)

static var _releasing: bool = false

static func cfg() -> Dictionary:
	return CityServices.cfg().get("ambulance", {})

static func busy() -> bool:
	return not CityServices.pending.is_empty()

static func holding(fid: int) -> bool:
	for p in CityServices.pending:
		if int(p["fid"]) == fid:
			return true
	return false

static func hold(fid: int, severity: int, reason: String) -> bool:
	if _releasing or not CityServices.map_ready() or severity < int(cfg().get("hold_from_severity", 2)):
		return false
	var f = SysUtil.folk(fid)
	if f == null or int(f.household_id) <= 0 or bool(f.has_meta("visitor")):
		return false
	if holding(fid):
		return true
	var lot: String = NeighborhoodLots.lot_at(f.tile)
	if lot == str(CityServices.station("ambulance").get("lot", "hospital")):
		return false                                                      # already at the hospital: no ambulance needed
	if lot == "":
		lot = PlayerLots.home_of(f)
	var e: Dictionary = CityServices.dispatch("ambulance", lot, {"no_phone": f.has_buff("no_signal")})
	CityServices.pending.append({"fid": fid, "severity": severity, "reason": reason, "due": SysUtil.now() + int(e["minutes"]), "minutes": int(e["minutes"])})
	SysUtil.notify(str(CityServices.cfg().get("text", {}).get("on_way", "")).replace("{min}", str(int(e["minutes"]))), "info")
	return true

static func on_minute() -> void:
	var now: int = SysUtil.now()
	for p in CityServices.pending.duplicate():
		if int(p["due"]) <= now:
			CityServices.pending.erase(p)
			_arrive(p)

static func _arrive(p: Dictionary) -> void:
	var fid: int = int(p["fid"])
	var f = SysUtil.folk(fid)
	if f == null or Hospital.patients.has(fid):
		return
	var sev: int = int(p["severity"])
	var c: Dictionary = cfg()
	if int(p["minutes"]) > int(c.get("worsen_after", 18)) and sev < 3 and CityState.chance(float(c.get("worsen_chance", 0.5))):
		sev += 1
		CityServices.count("worsened")
		SysUtil.notify(str(CityServices.cfg().get("text", {}).get("late", "")).replace("{min}", str(int(p["minutes"]))).replace("{name}", str(f.name)), "warn")
	_releasing = true
	Hospital.admit(fid, sev, str(p["reason"]))
	_releasing = false
	SysUtil.game_event("ambulance_arrived", {"folk_id": fid, "minutes": int(p["minutes"])})
