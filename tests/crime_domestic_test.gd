extends RefCounted
## Task 19.1: domestic violence is rare, escalates in steps, never targets children, and has consequences that change the situation
## (protective order, moving out, divorce, escalating sentences, anger-management course).

const C = preload("res://tests/crime_kit.gd")
const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_family(f)
	_children(f)
	_orders(f)
	_leaving(f)
	_sentences(f)
	_course(f)
	return f

## Father (hot-headed), mother (married) and a child in the player household.
func _home(w: StubWorld) -> Array:
	var dad := K.make_folk(w, "Ivo Orr", ["hot_headed"], 1, Vector2i(13, 12))
	var mum := K.make_folk(w, "Tess Orr", [], 1, Vector2i(14, 12))
	var kid := K.make_folk(w, "Tobin Orr", [], 1, Vector2i(15, 12), "child")
	FamilyMarriage.propose_marriage(dad.id, mum.id)
	FamilyMarriage.marry(dad.id, mum.id)
	Family.link_parent(kid.id, dad.id)
	Family.link_parent(kid.id, mum.id)
	return [int(dad.id), int(mum.id), int(kid.id)]

func _family(f: Array) -> void:
	var w := C.town(6)
	var h: Array = _home(w)
	var dad: int = h[0]
	var mum: int = h[1]
	JusticePlayer.auto = "stay"
	var days: Array = []
	for d in 56:
		K.set_time(3 + d, 12)
		RelationshipRomance.add_tension(dad, mum, 100.0)
		RelationshipRomance.add_tension(mum, dad, 100.0)
		var before: int = JusticeState.counter("hit") + JusticeState.counter("shove")
		for i in 6:                               # six screaming arguments a day
			CrimeAssault.on_argument(dad, mum, 4)
		if JusticeState.counter("hit") + JusticeState.counter("shove") > before:
			days.append(3 + d)
	var hits: int = JusticeState.counter("hit")
	var all: int = hits + JusticeState.counter("shove")
	print("[crime_domestic] forced hot-headed pair, 56 days x 6 screaming arguments: %d shoves, %d hits (was 49 hits)" % [all - hits, hits])
	K.expect(f, hits <= 2 and all <= 8, "violence stays rare (%d incidents, %d hits in 56 days)" % [all, hits])
	var gap_ok: bool = true
	for i in range(1, days.size()):
		gap_ok = gap_ok and int(days[i]) - int(days[i - 1]) >= int(JusticeState.sect("assault").get("cooldown_shove", 7))
	K.expect(f, gap_ok, "the cooldown holds between incidents of the pair")
	# below the screaming level or tension nothing happens
	var n0: int = JusticeState.counter("hit") + JusticeState.counter("shove")
	JusticeState.violence.clear()
	for i in 1000:
		CrimeAssault.on_argument(dad, mum, 2)
	K.expect(f, JusticeState.counter("hit") + JusticeState.counter("shove") == n0, "arguments below the screaming level never turn physical")
	# released from custody: calm for a while
	JusticeState.violence.clear()
	JusticeState.inmates[dad] = {"case": 0, "kind": "jail", "since": 1, "until": 1, "behaviour": 50, "parole_day": -1}
	Prison.release(dad, false)
	K.set_time(70, 12)
	var n1: int = JusticeState.counter("hit") + JusticeState.counter("shove")
	RelationshipRomance.add_tension(dad, mum, 100.0)
	for i in 600:
		CrimeAssault.on_argument(dad, mum, 4)
	K.expect(f, JusticeState.counter("hit") + JusticeState.counter("shove") == n1, "no violence right after a release")
	JusticePlayer.auto = ""
	K.teardown()

func _children(f: Array) -> void:
	var w := C.town(6)
	var h: Array = _home(w)
	var dad: int = h[0]
	var kid: int = h[2]
	var tod := K.make_folk(w, "Tiny Orr", [], 1, Vector2i(16, 12), "toddler")
	var baby := K.make_folk(w, "Bit Orr", [], 1, Vector2i(17, 12), "baby")
	var tod_id: int = tod.id
	var baby_id: int = baby.id
	JusticePlayer.auto = "police"
	for v in [kid, tod_id, baby_id]:
		RelationshipRomance.add_tension(dad, v, 100.0)
		RelationshipRomance.add_tension(v, dad, 100.0)
		for i in 1200:
			if i % 50 == 0:
				JusticeState.violence.clear()
			CrimeAssault.on_argument(dad, v, 4)
			CrimeAssault.on_argument(v, dad, 4)
			CrimeAssault.escalate(dad, v)
			CrimeAssault.fight(dad, v, 2, "hit")
	K.expect(f, JusticeState.counter("hit") + JusticeState.counter("shove") == 0 and JusticeState.cases.is_empty(), "children, toddlers and babies are never targeted (thousands of rolls)")
	JusticePlayer.auto = ""
	K.teardown()

func _orders(f: Array) -> void:
	var w := C.town(8)
	var h: Array = _home(w)
	var dad: int = h[0]
	var mum: int = h[1]
	K.set_time(5, 12)
	JusticePlayer.auto = "police"
	var c: Dictionary = CrimeAssault.fight(dad, mum, 2, "hit")
	K.expect(f, not c.is_empty() and bool(c.get("domestic", false)), "a hit on a household member is a domestic case")
	c["accused"] = dad
	c["wrongful"] = false
	JusticeState.inmates.erase(dad)
	JusticeOrders.issue(c, JusticeOrders.days_for(dad))
	K.expect(f, not JusticeOrders.between(dad, mum).is_empty(), "a protective order is issued")
	K.expect(f, SysUtil.folk(dad) == null and Story.townies.has(dad), "the offender moved out of the shared home")
	K.expect(f, JusticeOrders.bars(dad, mum) and JusticeOrders.bars(dad, int(h[2])), "the order keeps them away from the victim and the household")
	var o: Dictionary = JusticeOrders.between(dad, mum)
	var viol: Dictionary = JusticeOrders.violate(o)
	K.expect(f, str(viol.get("kind", "")) == "order_violation" and JusticeState.counter("arrests") >= 1, "breaking the order is a crime that leads to an arrest")
	K.expect(f, int(JusticeOrders.between(dad, mum)["until"]) > SysUtil.day() + 28, "a violation extends the order")
	K.set_time(5 + 400, 12)
	JusticeOrders.on_day()
	K.expect(f, JusticeOrders.between(dad, mum).is_empty() or CrimePerson.alive(dad) == false, "orders expire")
	JusticePlayer.auto = ""
	K.teardown()
	# conviction of a townie pair: an order that is longer for repeat offenders
	var w2 := C.town(10)
	var ids: Array = C.adults()
	var a: int = int(ids[0])
	var b: int = int(ids[1])
	C.set_family(a, b)
	JusticeState.sect("domestic")["domestic_report"] = 1.0
	K.set_time(5, 12)
	var c2: Dictionary = CrimeAssault.fight(a, b, 2, "hit")
	K.expect(f, not c2.is_empty() and bool(c2["domestic"]), "a domestic case between relatives")
	c2["accused"] = a
	c2["culprit"] = a
	c2["charge"] = "assault"
	c2["verdict"] = "guilty"
	JusticeSentence.impose(c2)
	var first: int = int(JusticeOrders.between(a, b).get("until", 0)) - SysUtil.day()
	K.expect(f, first >= 28, "a conviction brings a protective order (%d days)" % first)
	K.teardown()

func _leaving(f: Array) -> void:
	# the household victim chooses: make them leave
	var w := C.town(6)
	var h: Array = _home(w)
	JusticePlayer.auto = "separate"
	CrimeAssault.fight(h[0], h[1], 2, "hit")
	K.expect(f, SysUtil.folk(h[0]) == null and FamilyTree.spouse_of(h[1]) != h[0], "the victim can make the offender leave: divorce and move out")
	JusticePlayer.auto = ""
	K.teardown()
	# or leave with the kids
	var w2 := C.town(6)
	var h2: Array = _home(w2)
	JusticePlayer.auto = "leave"
	CrimeAssault.fight(h2[0], h2[1], 2, "hit")
	K.expect(f, SysUtil.folk(h2[1]) == null and SysUtil.folk(h2[2]) == null and SysUtil.folk(h2[0]) != null, "the victim can leave and take the kids")
	JusticePlayer.auto = ""
	K.teardown()
	# townie partners: the victim sometimes ends it
	var w3 := C.town(12)
	var ids: Array = C.adults()
	var gone: int = 0
	for i in 40:
		var a: int = int(ids[0])
		var b: int = int(ids[1])
		RelationshipRomance.start_dating(a, b, false)
		JusticeState.violence.clear()
		CrimeAssault.fight(a, b, 2, "hit")
		if not RelationshipRomance.exclusive_partners(b).has(a):
			gone += 1
	K.expect(f, gone > 5 and gone < 35, "townie victims sometimes end the relationship (%d of 40)" % gone)
	K.teardown()

func _sentences(f: Array) -> void:
	var w := C.town(8)
	var ids: Array = C.adults()
	var pid: int = int(ids[0])
	var c: Dictionary = {"accused": pid, "charge": "assault", "kind": "assault", "counts": 1}
	K.set_time(5, 12)
	var first_inside: int = 0
	for i in 300:
		if str(JusticeSentence.pick(c, false)["type"]) in ["jail", "prison"]:
			first_inside += 1
	JusticeState.records[pid] = [{"day": 1, "charge": "assault", "case": 1, "result": "guilty"}, {"day": 2, "charge": "assault", "case": 2, "result": "guilty"},
		{"day": 3, "charge": "assault", "case": 3, "result": "guilty"}]
	var third_inside: int = 0
	var third_light: int = 0
	for i in 300:
		var t: String = str(JusticeSentence.pick(c, false)["type"])
		if t in ["jail", "prison"]:
			third_inside += 1
		if t == "fine":
			third_light += 1
	K.expect(f, third_inside > first_inside + 60 and third_inside > 200, "repeat offenders are sent away far more often (%d vs %d of 300)" % [third_inside, first_inside])
	K.expect(f, third_light < 15, "the fourth assault is almost never a fine (%d of 300)" % third_light)
	K.teardown()

func _course(f: Array) -> void:
	var w := C.town(6)
	var h: Array = _home(w)
	var dad: int = h[0]
	var base: float = CrimeAssault.temper(dad)
	CrimeFlow.on_game_event("anger_course", {"folk_id": dad})
	K.expect(f, CrimeAssault.temper(dad) < base * 0.5 and SysUtil.folk(dad).has_buff("calm_mind"), "an anger-management course lowers the temper of a hot-headed folk for a while")
	K.set_time(5 + 60, 12)
	K.expect(f, is_equal_approx(CrimeAssault.temper(dad), base), "the effect wears off")
	# as a sentence part: a mandatory course after the sentence is handed down
	var c: Dictionary = {"id": 99, "accused": dad, "charge": "domestic_violence", "kind": "assault", "verdict": "guilty", "domestic": false}
	JusticeSentence._apply(c, dad, {"type": "probation", "days": 10, "courses": [{"kind": "anger_management", "days": 2}]})
	K.expect(f, JusticeState.courses.has(dad), "the course is a sentence part")
	for d in 3:
		K.set_time(70 + d, 12)
		JusticeSentence.on_day()
	K.expect(f, not JusticeState.courses.has(dad) and CrimeAssault.temper(dad) < base * 0.5, "finishing the court-ordered course calms them")
	K.teardown()
