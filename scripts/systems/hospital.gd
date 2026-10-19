class_name Hospital
extends RefCounted
## The hospital rabbit hole. No map lot: a patient simply leaves through Away (reason "hospital", hidden on the map) for N hours,
## carries the hidden `in_hospital` buff, and comes back with a bill (scaled by severity; Incidents.insurance_cover() pays part).
##   Hospital.admit(folk_id, severity 1..3, reason) -> bool      Hospital.discharge(folk_id)     Hospital.is_in(folk or id)
##   Hospital.injure(folk, severity, reason) / fall_ill(...)     marker buffs `injured` / `sick`; severity >= min_admit_severity also admits
## Far townies use the statistical version: marked in_hospital in their Story record, back (or dead, per
## config.hospital.townie_death_chance) when the stay is over, resolved in on_hour(). Data: config.hospital in data/incidents.json.

static var patients: Dictionary = {}     # id -> {severity, reason, admitted_min, until_min, bill, townie, hid}

static func reset() -> void:
	patients.clear()

static func cfg() -> Dictionary:
	return IncidentDefs.cfg("hospital", {})

static func _by_sev(table: String, sev: int, default_v: float) -> float:
	return float((cfg().get(table, {}) as Dictionary).get(str(clampi(sev, 1, 3)), default_v))

static func is_in(x) -> bool:
	var id: int = int(x.id) if x is Folk else int(x)
	return patients.has(id)

static func info(id: int) -> Dictionary:
	return patients.get(id, {})

# ------------------------------------------------------------------ markers
static func _timed_buff(f, buff: String, hours: float) -> void:
	f.add_buff(buff)
	for b in f.buffs:
		if str(b["id"]) == buff:
			b["remaining"] = maxf(float(b["remaining"]), hours * 60.0)

## Injuries and illness are kept by the Health layer (task 02: severity, slow walking, limits, contagion); these stay the entry points.
static func injure(f, severity: int, reason: String = "") -> void:
	Health.injure(f, severity, reason)

static func fall_ill(f, severity: int, reason: String = "") -> void:
	Health.fall_ill(f, "generic", severity, reason)

# ------------------------------------------------------------------ admit / discharge
static func admit(folk_id: int, severity: int, reason: String = "") -> bool:
	severity = clampi(severity, 1, 3)
	if patients.has(folk_id):
		return false
	if CityAmbulance.hold(folk_id, severity, reason):       # task 12: an ambulance has to come first (real map, residents)
		return true
	var mins: float = _by_sev("stay_hours", severity, 16.0) * 60.0
	var f = SysUtil.folk(folk_id)
	var rec: Dictionary = {"severity": severity, "reason": reason, "admitted_min": SysUtil.now(), "until_min": SysUtil.now() + int(mins),
		"bill": int(_by_sev("bill", severity, 100.0)), "townie": f == null, "hid": int(f.household_id) if f != null else 0}
	if f == null:
		if not Story.townies.has(folk_id) or not bool(Story.townies[folk_id]["alive"]):
			return false
		patients[folk_id] = rec
		Story.townies[folk_id]["in_hospital"] = true
		return true
	if Away.is_away(folk_id):
		Away.recall(folk_id, "hospital")
	Health.on_admitted(f)                        # a collapsed patient is brought round first (the lying-down interaction would block the stay)
	patients[folk_id] = rec
	f.add_buff("in_hospital")
	if HospitalWard.lot_id() != "" and HospitalWard.place(f, rec):        # a real bed in the hospital building (task 10): full simulation
		SysUtil.game_event("admitted", {"folk_id": folk_id, "severity": severity, "reason": reason})
		return true
	if not Away.send(f, mins, "hospital", {"label": "In hospital", "severity": severity}):
		patients.erase(folk_id)
		f.remove_buff("in_hospital")
		return false
	SysUtil.game_event("admitted", {"folk_id": folk_id, "severity": severity, "reason": reason})
	return true

## Send a patient home now (still pays the bill).
static func discharge(folk_id: int) -> bool:
	if not patients.has(folk_id):
		return false
	var f = SysUtil.folk(folk_id)
	if f == null:
		_finish_townie(folk_id)
		return true
	if Away.is_away(folk_id):
		return Away.recall(folk_id, "discharged")
	var ward: Dictionary = patients.get(folk_id, {})
	if bool(ward.get("ward", false)):                              # a real bed: leave it and go home first
		HospitalWard.release(f, ward)
	on_returned(f, {"reason": "hospital", "completed": false})   # still queued, never left
	for q in f.queue.duplicate():
		if (q as Interaction).def_id == Away.IID:
			f.queue.erase(q)
	Away.pending.erase(folk_id)
	return true

## Away finished (stay over or recalled): remove the marker, pay, heal a little.
static func on_returned(f, _rec: Dictionary) -> void:
	var p: Dictionary = patients.get(int(f.id), {})
	patients.erase(int(f.id))
	f.remove_buff("in_hospital")
	if p.is_empty():
		return
	f.remove_buff("injured")
	f.remove_buff("sick")
	Health.on_discharged(f)
	var paid: int = charge(int(p.get("hid", f.household_id)), int(p["bill"]), str(f.name))
	SysUtil.notify("%s is home from hospital. The bill was %d coins." % [f.name, paid] if paid > 0 else "%s is home from hospital." % f.name, "info")
	SysUtil.game_event("discharged", {"folk_id": int(f.id), "bill": paid})

## Pay `amount` (minus insurance) now, or leave an ordinary bill when the household cannot afford it. Returns the net amount.
static func charge(hid: int, amount: int, who: String = "") -> int:
	var net: int = maxi(amount - Incidents.insurance_cover(amount, hid, "health"), 0)
	if net <= 0 or hid <= 0:
		return net
	if Economy.spend(hid, net, "hospital bill"):
		return net
	var bill: Dictionary = {"id": Economy._seq, "hid": hid, "amount": net, "base": net, "issued": SysUtil.day(), "due": SysUtil.day() + 3,
		"paid": false, "late": false, "fee": 0, "reason": "hospital"}
	Economy._seq += 1
	Economy.bills.append(bill)
	SysUtil.notify("The hospital bill for %s (%d coins) is waiting to be paid." % [who, net], "bill")
	return net

# ------------------------------------------------------------------ far townies
static func on_hour() -> void:
	var due: Array = []
	var ward_due: Array = []
	for id in patients:
		var p: Dictionary = patients[id]
		if bool(p["townie"]) and SysUtil.now() >= int(p["until_min"]):
			due.append(int(id))
		elif bool(p.get("ward", false)):
			if SysUtil.now() >= int(p["until_min"]):
				ward_due.append(int(id))
			else:
				var f = SysUtil.folk(int(id))
				if f != null and not HospitalWard.has_stay(f):         # after a load the stay interaction is gone: lie back down
					var bed = WorldIface.get_object(int(p.get("bed", -1)))
					if bed != null:
						HospitalWard._queue_stay(f, bed, float(int(p["until_min"]) - SysUtil.now()))
	due.sort()
	ward_due.sort()
	for id in due:
		_finish_townie(id)
	for id2 in ward_due:
		discharge(id2)

static func _finish_townie(tid: int) -> void:
	var p: Dictionary = patients.get(tid, {})
	patients.erase(tid)
	var t: Dictionary = Story.townies.get(tid, {})
	if t.is_empty() or p.is_empty():
		return
	t.erase("in_hospital")
	if Incidents.rng.randf() < _by_sev("townie_death_chance", int(p["severity"]), 0.0) * CityServices.death_mult():      # task 12: slow ambulances cost lives
		Aging.kill(tid, "illness")
	else:
		Story._log("%s came home from hospital." % t["name"])
		ChronicleHook.note("hospital", "%s came home from hospital." % t["name"], [tid], "town:%d" % int(t.get("lot", 0)), 1, false)

# ------------------------------------------------------------------ UI helper
## Status chips for the folk panel: [{text, color, tip}].
static func status_chips(f) -> Array:
	var out: Array = []
	if is_in(f):
		out.append({"text": "In hospital", "color": Color("#e5534b"), "tip": "Being looked after at the hospital. Back at %s." % _clock_text(int(patients[int(f.id)]["until_min"]))})
	if f.has_buff("injured"):
		out.append({"text": "Injured", "color": Color("#e8913d"), "tip": "Hurt. Rest helps; a bad injury needs the hospital."})
	if f.has_buff("sick"):
		out.append({"text": Health.sick_label(f), "color": Color("#c9b037"), "tip": "Feeling ill. Rest, food and a doctor help."})
	out.append_array(Health.status_chips(f))
	return out

static func _clock_text(total_min: int) -> String:
	return "day %d, %02d:%02d" % [total_min / 1440 + 1, (total_min / 60) % 24, total_min % 60]

static func to_dict() -> Dictionary:
	return {"patients": SysUtil.str_keys(patients).duplicate(true)}

static func from_dict(d: Dictionary) -> void:
	reset()
	var src: Dictionary = d.get("patients", {})
	for k in src:
		var r: Dictionary = (src[k] as Dictionary).duplicate(true)
		SysUtil.ints_in(r, ["severity", "admitted_min", "until_min", "bill", "hid", "bed", "baby"])
		patients[int(str(k))] = r