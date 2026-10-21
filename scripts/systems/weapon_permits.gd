class_name WeaponPermits
extends RefCounted
## Task 57: permits, the background check and the carrying rules. A gun is legal only with a permit; a banned blade or an unregistered
## gun carried in public is its own petty charge. The check is real: it reads the justice record (a violent or recent conviction refuses
## a gun permit; a child cannot hold one). A permit takes `wait_days` to come through.
##   WeaponPermits.apply(pid, permit) -> {ok, reason, ready_day}   WeaponPermits.has(pid, permit)
##   WeaponPermits.carry_charge(pid, weapon_id) -> "" or a charge id   WeaponPermits.searched(pid, place)

const VIOLENT := ["assault", "domestic_violence", "aggravated_assault", "attempted_murder", "murder", "manslaughter", "robbery",
	"kidnapping", "child_abuse", "child_endangerment", "elder_abuse", "vehicular_manslaughter", "resisting_arrest", "escape", "hit_and_run"]

static var permits: Dictionary = {}      # pid -> {permit_id: ready_day (granted when day >= ready_day)}
static var history: Dictionary = {}      # pid -> [{permit, day, ok, reason}]

static func reset() -> void:
	permits = {}
	history = {}

static func cfg() -> Dictionary:
	return SysUtil.table("weapons").get("permits", {})

static func def(id: String) -> Dictionary:
	return (cfg() as Dictionary).get(id, {})

static func def_weapon(weapon_id: String) -> Dictionary:
	return (SysUtil.table("weapons").get("weapons", {}) as Dictionary).get(weapon_id, {})

static func carry_cfg() -> Dictionary:
	return SysUtil.table("weapons").get("carry", {})

static func record_cfg() -> Dictionary:
	return SysUtil.table("weapons").get("records", {})

static func _recent_days() -> int:
	return int(record_cfg().get("recent_days", 365))

# ------------------------------------------------------------------ the background check
static func under_21(pid: int) -> bool:
	return CrimePerson.stage(pid) in ["baby", "toddler", "child", "teen"]

static func _counts(r: Dictionary) -> bool:
	return str(r.get("result", "")) in ["guilty", "plea", "petty", "convicted"]

static func violent_record(pid: int) -> bool:
	for r in JusticeRecords.visible(pid):
		if _counts(r) and VIOLENT.has(str(r.get("charge", ""))):
			return true
	return false

static func recent_record(pid: int) -> bool:
	var cut: int = SysUtil.day() - _recent_days()
	for r in JusticeRecords.visible(pid):
		if _counts(r) and int(r.get("day", 0)) >= cut:
			return true
	return false

## "" when allowed, else the plain reason.
static func refused(pid: int, permit_id: String) -> String:
	for key in (def(permit_id).get("refused_if", []) as Array):
		match str(key):
			"violent_record":
				if violent_record(pid):
					return "a violent conviction on the record"
			"recent_record":
				if recent_record(pid):
					return "a conviction in the last %s" % SysUtil.count_text(maxi(_recent_days() / 365, 1), "year")
			"under_21":
				if under_21(pid):
					return "being under 21"
	return ""

static func has(pid: int, permit_id: String) -> bool:
	var d: Dictionary = permits.get(pid, {})
	return d.has(permit_id) and SysUtil.day() >= int(d[permit_id])

## Apply at the counter. Granted after the permit's wait_days; refused by the record.
static func apply(pid: int, permit_id: String) -> Dictionary:
	var d: Dictionary = def(permit_id)
	if d.is_empty():
		return {"ok": false, "reason": "no such permit", "ready_day": -1}
	if has(pid, permit_id):
		return {"ok": true, "reason": "already held", "ready_day": int(permits[pid][permit_id])}
	var why: String = refused(pid, permit_id)
	if not history.has(pid):
		history[pid] = []
	(history[pid] as Array).append({"permit": permit_id, "day": SysUtil.day(), "ok": why == "", "reason": why})
	if why != "":
		if CrimePerson.is_player(pid):
			SysUtil.notify("The permit is refused: %s." % why, "warn")
		return {"ok": false, "reason": why, "ready_day": -1}
	if not permits.has(pid):
		permits[pid] = {}
	permits[pid][permit_id] = SysUtil.day() + int(d.get("wait_days", 0))
	if CrimePerson.is_player(pid):
		SysUtil.notify("The %s is granted in %s." % [str(d.get("label", permit_id)).to_lower(), SysUtil.count_text(int(d.get("wait_days", 0)), "day")], "good")
	return {"ok": true, "reason": "", "ready_day": int(permits[pid][permit_id])}

## A gun sold at the counter is registered to the buyer's household (the serial already exists on the Inventory entry).
static func register_gun(pid: int, weapon_id: String) -> Dictionary:
	var hid: int = CrimePerson.hid(pid)
	for e in Inventory.items(pid):
		if str(e["id"]) == weapon_id and int(e.get("registered_to", -1)) < 0:
			e["registered_to"] = hid
			return e
	return {}

# ------------------------------------------------------------------ carrying
static func place_forbids(place: String) -> bool:
	return (carry_cfg().get("never_allowed", []) as Array).has(place)

## "" when the weapon may be carried as it is, else the charge id from weapons.json.
static func carry_charge(pid: int, weapon_id: String) -> String:
	var d: Dictionary = def_weapon(weapon_id)
	var legal: String = str(d.get("legal", "free"))
	var charge: String = str(d.get("carry_charge", ""))
	if legal == "banned":
		return charge if charge != "" else "banned_weapon"
	if legal == "permit":
		if not has(pid, str(d.get("permit", "gun"))):
			return charge if charge != "" else "unlicensed_gun"
		if str(d.get("kind", "")) == "firearm":
			for e in Inventory.items(pid):
				if str(e["id"]) == weapon_id and int(e.get("registered_to", -1)) < 0:
					return charge if charge != "" else "unlicensed_gun"
	return ""

## A frisk / screening. Returns the concealed weapons found and any charge raised (settled as a petty offence).
static func searched(pid: int, place: String) -> Dictionary:
	var found: Array = []
	var charges: Array = []
	for e in Inventory.items(pid):
		var id: String = str(e["id"])
		var d: Dictionary = def_weapon(id)
		if d.is_empty():
			continue
		if str(d.get("conceal", "none")) != "none":
			found.append(id)
		var ch: String = carry_charge(pid, id)
		if ch != "" and (place_forbids(place) or str(d.get("conceal", "none")) != "none"):
			charges.append(ch)
			charge_carry(pid, id, ch)
	return {"found": found, "charges": charges}

## A petty case for carrying illegally (no trial; a fine or service, like CrimePetty.commit).
static func charge_carry(pid: int, weapon_id: String, charge: String = "") -> Dictionary:
	var ch: String = charge if charge != "" else carry_charge(pid, weapon_id)
	if ch == "":
		return {}
	var scene: String = CrimePlace.where_now(pid)
	var c: Dictionary = CaseStore.create(ch, pid, -1, scene, {"witnessed": true, "witness_clarity": 0.9, "witnesses": [], "trace": 0.4})
	c["state"] = "open"
	c["disc_day"] = SysUtil.day()
	c["charge"] = ch
	c["accused"] = pid
	CrimePlace.place_at_scene(pid, scene)
	CrimePetty.settle(c)
	return c

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {"permits": SysUtil.str_keys(permits).duplicate(true), "history": SysUtil.str_keys(history).duplicate(true)}

static func from_dict(d: Dictionary) -> void:
	reset()
	for k in (d.get("permits", {}) as Dictionary):
		permits[int(str(k))] = (d["permits"][k] as Dictionary).duplicate(true)
	for k2 in (d.get("history", {}) as Dictionary):
		history[int(str(k2))] = (d["history"][k2] as Array).duplicate(true)
