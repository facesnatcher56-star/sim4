extends RefCounted
## One toast per trip (asking again while already walking there changes nothing) and the hospital is not a hangout:
## only a patient or a visitor of a patient they know may go.

const Kit = preload("res://tests/hood_kit.gd")

func run() -> Array:
	var fails: Array = []
	var folk: Array = Kit.new_game("classic")
	Kit.set_time(2, 12)
	Kit.run(3)
	var mira: Folk = folk[0]
	var tobin: Folk = folk[1]
	var notes: Array = []
	SimEnv.events().notification.connect(func(t, k): notes.append([str(t), str(k)]))
	var r1: Dictionary = Neighborhood.travel([mira.id], "park", {})
	var n1: int = notes.filter(func(n): return n[1] == "travel").size()
	Kit.run(2)
	var r2: Dictionary = Neighborhood.travel([mira.id], "park", {})
	Kit.run(2)
	var r3: Dictionary = Neighborhood.travel([mira.id], "park", {})
	var n2: int = notes.filter(func(n): return n[1] == "travel" and n[0].find("head to") >= 0).size()
	if not bool(r1["ok"]) or bool(r2["ok"]) or bool(r3["ok"]) or n2 != 1:
		fails.append("one 'head to' toast per trip (first ok=%s, repeats ok=%s/%s, toasts %d, travel toasts at first %d)" % [r1["ok"], r2["ok"], r3["ok"], n2, n1])
	var h: Dictionary = Neighborhood.can_travel([tobin.id], "hospital")
	if bool(h["ok"]):
		fails.append("a healthy resident with nobody in hospital cannot go to the hospital")
	Hospital.patients[int(mira.id)] = {"severity": 1, "reason": "test", "admitted_min": SysUtil.now(), "until_min": SysUtil.now() + 600, "bill": 0, "townie": false, "hid": 1}
	var h2: Dictionary = Neighborhood.can_travel([tobin.id], "hospital")
	if not bool(h2["ok"]):
		fails.append("a housemate may visit a patient: %s" % str(h2.get("reason", "")))
	Hospital.patients.erase(int(mira.id))
	Kit.teardown()
	return fails
