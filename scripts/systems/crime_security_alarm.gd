class_name CrimeSecurityAlarm
extends RefCounted
## Alarm company response and FALSE ALARMS. An alarm that rings calls the police through the company: a monitored alarm brings them much faster.
## Now and then an alarm goes off for nothing (a cat, a gust, a forgotten code): a small fee, and after a few strikes the police take false alarms
## from that house less seriously for a while (slower response). Insurance gives a discount for alarms, cameras and good locks.

static func cfg() -> Dictionary:
	return CrimeSecurity.cfg()

## Minutes until the police arrive at `scene` after an alarm (a home with ignored alarms is slower).
static func response_delay(scene: String) -> int:
	var fx: Dictionary = CrimeSecurity.effects(CrimeSecurity.profile_for(scene))
	var d: int = int(fx["response_min"])
	if scene.begins_with("home:") and ignored(int(scene.get_slice(":", 1))):
		d *= 3
	return d

static func ignored(hid: int) -> bool:
	return int(CrimeLifeState.alarms.get(hid, {}).get("ignore_until", -1)) >= SysUtil.day()

## The alarm rang for a real crime in progress: the police are called with the right delay. Returns true if the company took the call.
static func ring(c: Dictionary, scene: String) -> bool:
	var p: Dictionary = CrimeSecurity.profile_for(scene)
	if not bool(p.get("alarm", false)):
		return false
	c["alarm_rang"] = true
	Police.respond(c, response_delay(scene))
	c["called"] = true
	return true

## Daily: false alarms for homes with an alarm.
static func on_day() -> void:
	var k: Dictionary = cfg()
	for hid in Economy.household_ids():
		var p: Dictionary = CrimeSecurity.home_profile(int(hid))
		if not bool(p["alarm"]):
			continue
		var pr: float = float(k.get("false_alarm_daily", 0.012)) * (1.5 if int(p["motion"]) > 0 else 1.0)
		if CrimeLifeState.chance(pr):
			false_alarm(int(hid), bool(p["monitored"]))

static func false_alarm(hid: int, monitored: bool) -> void:
	var k: Dictionary = cfg()
	var rec: Dictionary = CrimeLifeState.alarms.get(hid, {"strikes": 0, "ignore_until": -1, "last": -1})
	rec["strikes"] = int(rec["strikes"]) + 1
	rec["last"] = SysUtil.day()
	var fee: int = int(k.get("false_alarm_fine", 12)) if monitored else 0
	if fee > 0:
		Economy.deposit(hid, -mini(fee, WorldIface.get_coins(hid)), "false alarm callout")
	var text: String = "The alarm went off for no reason" + (" - the company charged %d coins for the callout." % fee if fee > 0 else ".")
	if int(rec["strikes"]) >= int(k.get("false_alarm_strikes", 3)):
		rec["strikes"] = 0
		rec["ignore_until"] = SysUtil.day() + int(k.get("false_alarm_ignore_days", 14))
		text += " Too many false alarms: the police will be slower to come for a while."
	CrimeLifeState.alarms[hid] = rec
	CrimeLifeState.count("false_alarms")
	for r in SysUtil.residents():
		if int(r.household_id) == hid:
			SysUtil.notify(text, "warn")
			break

## Share off the home insurance premium for the cover at home (alarm, monitoring, cameras, good locks).
static func insurance_mult(hid: int) -> float:
	var d: Dictionary = cfg().get("insurance", {})
	var p: Dictionary = CrimeSecurity.home_profile(hid)
	var cut: float = 0.0
	if bool(p["alarm"]):
		cut += float(d.get("alarm", 0.08))
	if bool(p["monitored"]):
		cut += float(d.get("monitored", 0.07))
	if int(p["cameras"]) > 0:
		cut += float(d.get("camera", 0.05))
	if int(p["lock"]) >= 2:
		cut += float(d.get("lock", 0.05))
	return 1.0 - minf(cut, float(d.get("cap", 0.3)))

## Economy.compute_bill hook: weekly alarm monitoring and any hired guard.
static func bill_extra(hid: int) -> int:
	var svc: Dictionary = CrimeLifeState.home_sec.get(hid, {})
	if svc.is_empty():
		return 0
	var total: int = 0
	if bool(svc.get("monitored", false)):
		total += int(cfg().get("monitoring_weekly", 18))
	var g: int = int(svc.get("guard", 0))
	if g > 0:
		total += int((cfg().get("upgrades", {}).get("guard", {}).get("weekly", [0]) as Array)[mini(g, 2)])
	return total
