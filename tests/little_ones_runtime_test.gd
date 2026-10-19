extends RefCounted
## Babies, toddlers and children never do repairs, calls or paperwork (task 19j): a home with a baby, a toddler and a child, plus two adults, is hit with every kind of
## trouble the chaos counterplay answers (leak, broken things, roaches, gas) for 3 game days with the autonomy switched on. Nothing the little ones start may carry a tag
## their stage forbids (data/aging.json), and none of them ever starts a chaos counterplay interaction.

const K = preload("res://tests/systems_kit.gd")
const Kit = preload("res://tests/sim_testkit.gd")

const COUNTERPLAY := ["fix_leak", "check_pipes", "call_plumber", "call_handyperson", "call_exterminator", "set_roach_traps", "shut_off_gas", "call_gas_company", "report_identity_theft"]
const TROUBLE := ["plumbing_trouble", "broken_things", "roaches_seen", "gas_smell", "identity_theft"]

var _started: Array = []

func _on_start(fid: int, iid: String, _t: int) -> void:
	var p = SysUtil.folk(fid)
	if p != null and str(p.age_stage) in ["baby", "toddler", "child"]:
		_started.append([str(p.age_stage), iid])

func run() -> Array:
	var f: Array = []
	var w := K.setup(77)
	var o: Dictionary = Kit.furnish(w)
	SysContent.install_all()
	o["mailbox"] = w.add_object("mailbox", Vector2i(30, 30))
	WorldIface.coins[1] = 3000
	var a := K.make_folk(w, "Ann Rowe", [], 1, Vector2i(11, 14))
	var b := K.make_folk(w, "Bo Rowe", [], 1, Vector2i(13, 14))
	var baby := K.make_folk(w, "Pip Rowe", [], 1, Vector2i(12, 13), "baby")
	var tod := K.make_folk(w, "Kit Rowe", [], 1, Vector2i(14, 13), "toddler")
	var kid := K.make_folk(w, "Cy Rowe", [], 1, Vector2i(15, 13), "child")
	var all: Array = [a, b, baby, tod, kid]
	var dir = K.director()
	SimEnv.events().interaction_started.connect(_on_start)
	K.set_time(2, 6, 0)
	for m in 3 * 1440:
		if m % 60 == 0:
			for p in all:
				for t in TROUBLE:
					if not p.has_buff(t):
						p.add_buff(t)
		K.run(dir, 1)
	SimEnv.events().interaction_started.disconnect(_on_start)
	var defs: Dictionary = SimEnv.data().interactions()
	var seen: Dictionary = {}
	for e in _started:
		seen["%s:%s" % [e[0], e[1]]] = true
		K.expect(f, not COUNTERPLAY.has(e[1]), "a %s started %s" % [e[0], e[1]])
		var sd: Dictionary = Aging.stage_def(str(e[0]))
		var tags: Array = (defs.get(e[1], {}) as Dictionary).get("tags", [])
		for t in sd.get("forbid_tags", []):
			K.expect(f, not tags.has(t), "a %s started %s, which is tagged '%s'" % [e[0], e[1], t])
		var allow: Array = sd.get("allow_tags", [])
		if allow.size() > 0 and tags.size() > 0:
			var ok: bool = false
			for t in allow:
				ok = ok or tags.has(t)
			K.expect(f, ok, "a %s started %s, which is none of %s" % [e[0], e[1], allow])
	# the handler refuses them too, whatever queued the event
	for ev in COUNTERPLAY:
		for st in ["baby", "toddler", "child"]:
			var fake := Folk.create("X", [])
			fake.age_stage = st
			K.expect(f, not ChaosClock.counterplay_ok(fake, ev), "the handler refuses a %s for %s" % [st, ev])
		var grown := Folk.create("Y", [])
		grown.age_stage = "adult"
		K.expect(f, ChaosClock.counterplay_ok(grown, ev), "the handler accepts an adult for %s" % ev)
	var teen := Folk.create("T", [])
	teen.age_stage = "teen"
	K.expect(f, not ChaosClock.counterplay_ok(teen, "fix_leak") and ChaosClock.counterplay_ok(teen, "call_plumber"), "a teen may call the plumber but not fix the pipe")
	K.expect(f, _started.size() > 20, "the little ones did things at all (%d interactions)" % _started.size())
	K.teardown()
	return f
