class_name CrimeSecurity
extends RefCounted
## Task 21, part 2: security systems for homes and businesses. A PROFILE is one plain dictionary no matter where it comes from:
##   {lock 0..3, windows n, alarm, monitored, cameras n, motion n, safe 0..2, lights n, dog, guards n, detective}
## Homes read it from the household's objects (door locks of three grades, window locks, burglar alarm, security cameras, motion sensors, safes,
## security lights, a guard-dog kennel) plus two services (monitoring, a hired guard); businesses from their type (bank, jeweller, museum, market ...)
## plus what their owner bought; far townie homes from their wealth (deterministic per lot, nothing stored).
## EFFECTS turn a profile into numbers the crime code uses: harder entry, a burglar giving up, more detection, camera footage, how fast help comes.

static func cfg() -> Dictionary:
	return CrimeLifeState.sect("security")

static func home_cfg() -> Dictionary:
	return cfg().get("home", {})

static func empty() -> Dictionary:
	return {"lock": 0, "windows": 0, "alarm": false, "monitored": false, "cameras": 0, "motion": 0, "safe": 0, "lights": 0, "dog": false, "guards": 0, "detective": false}

# ------------------------------------------------------------------ profiles
static func home_profile(hid: int) -> Dictionary:
	var p: Dictionary = empty()
	for o in Economy.objects_of(hid):
		add_object(p, str(o.def_id))
	var svc: Dictionary = CrimeLifeState.home_sec.get(hid, {})
	p["monitored"] = bool(svc.get("monitored", false)) and bool(p["alarm"])
	p["guards"] = int(svc.get("guard", 0))
	return p

## Fold one object kind into a profile (also used by the tests and the build catalog).
static func add_object(p: Dictionary, def_id: String) -> void:
	match def_id:
		"door_lock": p["lock"] = maxi(int(p["lock"]), 1)
		"door_lock_2": p["lock"] = maxi(int(p["lock"]), 2)
		"door_lock_3": p["lock"] = maxi(int(p["lock"]), 3)
		"window_lock": p["windows"] = int(p["windows"]) + 1
		"burglar_alarm": p["alarm"] = true
		"security_camera": p["cameras"] = int(p["cameras"]) + 1
		"motion_sensor": p["motion"] = int(p["motion"]) + 1
		"safe": p["safe"] = maxi(int(p["safe"]), 1)
		"vault_safe": p["safe"] = maxi(int(p["safe"]), 2)
		"security_light": p["lights"] = int(p["lights"]) + 1
		"guard_dog_kennel": p["dog"] = true

## A business: its type's base cover plus the owner's upgrades (CrimeLifeState.biz_sec), whichever is better.
static func business_profile(btype: String, biz_id: int = -1) -> Dictionary:
	var p: Dictionary = empty()
	var base: Dictionary = (cfg().get("business", {}) as Dictionary).get(btype, {})
	var up: Dictionary = CrimeLifeState.biz_sec.get(biz_id, {})
	for key in ["lock", "cameras", "motion", "safe", "lights", "guards"]:
		var src: String = {"cameras": "camera", "lights": "light", "guards": "guard"}.get(key, key)
		p[key] = maxi(int(base.get(src, 0)), int(up.get(src, 0)))
	p["alarm"] = bool(int(base.get("alarm", 0)) > 0 or int(up.get("alarm", 0)) > 0)
	p["monitored"] = bool(p["alarm"]) and (int(base.get("monitored", 0)) > 0 or int(up.get("monitored", 0)) > 0)
	p["detective"] = int(base.get("detective", 0)) > 0 or int(up.get("detective", 0)) > 0
	if int(p["guards"]) == 0 and CrimeSecurityGuards.watchman_on():
		p["guards"] = 1                                                 # the night watchman covers a closed shop
		p["watchman"] = true
	return p

## A far townie's house: richer folk have better locks, alarms and cameras. Deterministic per lot number.
static func townie_profile(lot_no: int, coins: int) -> Dictionary:
	var p: Dictionary = empty()
	var tiers: Array = (cfg().get("townie_home", {}) as Dictionary).get("tiers", [])
	var row: Array = [0.0, 0.0, 0.0, 0.0]
	for t in tiers:
		if coins <= int(t[0]):
			row = [t[0], t[1], t[2], t[3]]
			break
	var h: int = absi((lot_no * 2654435761) % 1000)
	p["lock"] = 2 if float(h) / 1000.0 < float(row[1]) else (1 if h % 2 == 0 else 0)
	p["alarm"] = float((h * 7) % 1000) / 1000.0 < float(row[2])
	p["cameras"] = 1 if float((h * 13) % 1000) / 1000.0 < float(row[3]) else 0
	return p

## Whatever lock key reaches: "home:3" -> household profile, "town:5" -> a townie house, "biz:7" / "biz:bank" -> business.
static func profile_for(scene: String) -> Dictionary:
	if scene.begins_with("home:"):
		return home_profile(int(scene.get_slice(":", 1)))
	if scene.begins_with("town:"):
		var n: int = int(scene.get_slice(":", 1))
		var coins: int = 0
		for tid in CrimePerson.townies_only():
			if CrimePerson.lot_no(tid) == n:
				coins += CrimePerson.coins(tid)
		return townie_profile(n, coins)
	if scene.begins_with("biz:"):
		var key: String = scene.get_slice(":", 1)
		if key.is_valid_int():
			var b: Dictionary = BusinessState.get_biz(int(key))
			return business_profile(str(b.get("type", "")), int(key))
		return business_profile(key)
	return empty()

# ------------------------------------------------------------------ effects
## Numbers for the crime code. `night`: lights only help after dark. `jammer`: an alarm bypass kit weakens the alarm side.
static func effects(p: Dictionary, night: bool = true, jammer: float = 0.0) -> Dictionary:
	var h: Dictionary = home_cfg()
	var lock: int = int(p.get("lock", 0))
	var diff: float = float((h.get("lock", {}) as Dictionary).get(str(lock), 0.0)) + minf(float(p.get("windows", 0)), float(h.get("window_cap", 3))) * float(h.get("window_lock", 0.04))
	var abort: float = float((h.get("abort_lock", {}) as Dictionary).get(str(lock), 0.0)) + minf(float(p.get("windows", 0)), 3.0) * float(h.get("abort_window", 0.03))
	# detection is ADDITIVE (1 + what each piece of cover adds) so a fortress is noticeable without every number saturating
	var inc: float = 0.0
	if bool(p.get("alarm", false)):
		var al: float = float(h.get("monitored_detect", 0.8)) if bool(p.get("monitored", false)) else float(h.get("alarm_detect", 0.5))
		if int(p.get("motion", 0)) > 0:
			al += float(h.get("motion_alarm", 0.25))
		inc += al * (1.0 - clampf(jammer, 0.0, 0.9))
	var cams: int = mini(int(p.get("cameras", 0)), int(h.get("camera_cap", 3)))
	if cams > 0:
		inc += float(h.get("camera_detect", 0.12))
		abort += float(h.get("abort_camera", 0.04))
	if int(p.get("motion", 0)) > 0 and not bool(p.get("alarm", false)):
		inc += float(h.get("motion_detect", 0.25))
	if int(p.get("lights", 0)) > 0 and night:
		inc += float(h.get("light_detect", 0.1))
		abort += float(h.get("abort_light", 0.06))
	if bool(p.get("dog", false)):
		inc += float(h.get("dog_detect", 0.35))
		abort += float(h.get("dog_abort", 0.2))
	var guards: int = int(p.get("guards", 0))
	var guard_inc: float = float(guards) * float(cfg().get("guard", {}).get("detect_each", 0.35))
	if bool(p.get("detective", false)):
		inc += 0.2
	var resp: int = int(h.get("monitored_response_min", 5)) if bool(p.get("monitored", false)) else int(h.get("alarm_response_min", 16))
	return {"difficulty": diff, "abort": minf(abort, float(h.get("abort_cap", 0.6))), "detect": 1.0 + inc + guard_inc, "guard_inc": guard_inc, "footage": minf(float(cams) * float(h.get("camera_footage", 0.4)), 0.95),
		"response_min": resp, "alarm": bool(p.get("alarm", false)), "safe_share": float((h.get("safe_share", {}) as Dictionary).get(str(int(p.get("safe", 0))), 0.0)), "guards": guards}

## One-line plain description for the dialog.
static func describe(p: Dictionary) -> String:
	var bits: Array = []
	if int(p["lock"]) > 0:
		bits.append(["", "basic locks", "reinforced locks", "high-security locks"][int(p["lock"])])
	if bool(p["alarm"]):
		bits.append("a monitored alarm" if bool(p["monitored"]) else "an alarm")
	if int(p["cameras"]) > 0:
		bits.append("%d camera%s" % [int(p["cameras"]), "" if int(p["cameras"]) == 1 else "s"])
	if int(p["motion"]) > 0:
		bits.append("motion sensors")
	if int(p["safe"]) > 0:
		bits.append("a safe" if int(p["safe"]) == 1 else "a vault safe")
	if int(p["lights"]) > 0:
		bits.append("security lights")
	if bool(p["dog"]):
		bits.append("a guard dog")
	if int(p["guards"]) > 0:
		bits.append("%d guard%s" % [int(p["guards"]), "" if int(p["guards"]) == 1 else "s"])
	if bool(p["detective"]):
		bits.append("a store detective")
	if bits.is_empty():
		return "None to speak of."
	var line: String = ", ".join(bits)
	return line.substr(0, 1).to_upper() + line.substr(1) + "."

## Rough 0..100 score for the build-mode "how safe is this place" line.
static func score(p: Dictionary) -> int:
	var e: Dictionary = effects(p)
	return clampi(int(100.0 * (1.0 - (1.0 - float(e["abort"])) / (1.0 + (float(e["detect"]) - 1.0) * 0.8 + float(e["difficulty"]) * 2.0))), 0, 100)
