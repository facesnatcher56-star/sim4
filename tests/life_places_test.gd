extends RefCounted
## Task 14 core: the places engine (data, hours, staff, services, passes, the lot-hours hook, the life block save).

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_data(f)
	_hours(f)
	_staff(f)
	_services(f)
	_member(f)
	_save(f)
	return f

func _world(coins: int = 1000) -> StubWorld:
	var w := K.setup()
	K.make_folk(w, "Ann")
	WorldIface.coins[1] = coins
	Story.generate_townies(12)
	LifeTick.new_game()
	return w

func _data(f: Array) -> void:
	var w := _world()
	var handlers := ["lecture", "course", "enrol_preschool", "tutor"]
	K.expect(f, Places.all().size() >= 6, "places load from data/life (%d)" % Places.all().size())
	for pid in Places.all():
		var d: Dictionary = Places.def(pid)
		K.expect(f, not Neighborhood.lot(str(d.get("lot", ""))).is_empty(), "%s is hosted in a lot that exists (%s)" % [pid, str(d.get("lot", ""))])
		K.expect(f, d.has("label") and d.has("kind"), "%s has a label and a kind" % pid)
		var hr: Array = d.get("hours", [0, 24])
		K.expect(f, hr.size() == 2 and float(hr[0]) < float(hr[1]), "%s has sensible hours" % pid)
		for sid in Places.services(pid):
			var s: Dictionary = Places.services(pid)[sid]
			K.expect(f, float(s.get("price", 0)) >= 0.0 and s.has("label"), "%s/%s has a label and a price" % [pid, sid])
			var h: String = str(s.get("handler", ""))
			K.expect(f, h == "" or PlaceHandlers.known(h), "%s/%s uses a known handler (%s)" % [pid, sid, h])
			K.expect(f, Places.find_service(sid).get("place", "") == pid, "service id %s is unique to %s" % [sid, pid])
	K.teardown()

func _hours(f: Array) -> void:
	var w := _world()
	K.set_time(1, 10)                      # day 1 = Monday
	K.expect(f, Places.open_at("school") and not Places.open_at("college"), "Monday 10:00: the school is open, the college is not yet")
	K.set_time(1, 19)
	K.expect(f, Places.is_open("college") and Places.is_open("night_school") and not Places.open_at("school"), "Monday 19:00: college and night classes are open")
	K.set_time(6, 11)                      # Saturday morning
	K.expect(f, not Places.open_at("college") and not Places.open_at("night_school") and not Venues.is_open_type("school", SimEnv.now_min()), "weekends: college, night classes and the school lot are closed")
	K.expect(f, Places.status_text("night_school").begins_with("Opens"), "a closed place says when it opens (%s)" % Places.status_text("night_school"))
	K.set_time(1, 19)
	K.expect(f, Venues.is_open_type("school", SimEnv.now_min()), "the school lot stays open in the evening for the college")
	K.set_time(1, 23)
	K.expect(f, not Venues.is_open_type("school", SimEnv.now_min()), "and is shut at night")
	K.teardown()

func _staff(f: Array) -> void:
	var w := _world()
	K.expect(f, PlaceStaff.staffed("college") and PlaceStaff.roster("college").size() == 3, "every place is staffed (college: %d)" % PlaceStaff.roster("college").size())
	K.expect(f, PlaceStaff.who("school", "teacher") != "", "the school has a named teacher (%s)" % PlaceStaff.who("school", "teacher"))
	PlaceStaff.rosters["college"] = []
	K.set_time(1, 19)
	K.expect(f, Places.open_at("college") and not Places.is_open("college") and Places.status_text("college") == "Short of staff", "no staff: short of staff and closed")
	PlaceStaff.fill_all(false)
	K.expect(f, Places.is_open("college"), "hiring reopens it")
	# a matching townie is the staff member
	var t: Dictionary = Story.add_townie(-1.0, "Mina Hale", [], "teacher", 2)
	PlaceStaff.rosters["school"] = []
	PlaceStaff.fill_all(false)
	K.expect(f, PlaceStaff.names("school").has("Mina Hale") or PlaceStaff.names("college").has("Mina Hale"), "a townie with the matching job gets the post")
	# a closure day
	PlaceStaff.closures["college"] = {"day": 1, "why": "a burst pipe"}
	K.expect(f, not Places.is_open("college") and Places.status_text("college") == "Closed today", "a closure shuts the place for the day")
	K.set_time(2, 19)
	K.expect(f, Places.is_open("college"), "and it reopens the next day")
	K.teardown()

func _services(f: Array) -> void:
	var w := _world(500)
	var ann = SysUtil.folk(1)
	var kid := K.make_folk(w, "Kit", [], 1, Vector2i(14, 12), "child")
	K.set_time(1, 19)
	var r: Dictionary = PlaceUse.use(1, "night_school", "course_cooking_basics", {"instant": true})
	K.expect(f, bool(r["ok"]) and Economy.balance(1) == 500 - PlaceUse.price("night_school", "course_cooking_basics", 1), "a lesson costs its price and works (%s)" % str(r.get("reason", "")))
	K.expect(f, PlaceUse.why_not(1, "night_school", "course_cooking_basics") == "Already done today.", "once a day")
	K.expect(f, PlaceUse.why_not(int(kid.id), "night_school", "course_cooking_basics") == "Not for children." or PlaceUse.why_not(int(kid.id), "night_school", "course_cooking_basics").begins_with("Not for"), "children are kept out of the adult course (%s)" % PlaceUse.why_not(int(kid.id), "night_school", "course_cooking_basics"))
	K.set_time(1, 10)
	K.expect(f, PlaceUse.why_not(1, "night_school", "course_first_aid") != "", "a closed place refuses (%s)" % PlaceUse.why_not(1, "night_school", "course_first_aid"))
	K.set_time(2, 19)
	WorldIface.coins[1] = 3
	K.expect(f, PlaceUse.why_not(1, "night_school", "course_cooking_basics").begins_with("That costs"), "too poor is said in plain words")
	WorldIface.coins[1] = 500
	# the economy index changes the price
	var base: int = PlaceUse.price("college", "lecture_arts", 1)
	MarketEconomy.enabled = true
	MarketEconomy.price_idx = 1.25
	K.expect(f, PlaceUse.price("college", "lecture_arts", 1) > base, "prices follow the town economy (%d -> %d)" % [base, PlaceUse.price("college", "lecture_arts", 1)])
	MarketEconomy.enabled = false
	MarketEconomy.price_idx = 1.0
	# stage rule helper
	K.expect(f, Places.stage_reason("teen", {"adult_only": true}) == "Only for adults." and Places.stage_reason("adult", {"adult_only": true}) == "", "adult_only keeps teens out")
	K.expect(f, Places.stage_reason("child", {"stages": ["toddler"]}) != "", "stages lists are strict")
	# a visit goes through the interaction when the content is installed
	SysContent.install_all()
	K.set_time(3, 19)
	var dir = K.director()
	var r2: Dictionary = PlaceUse.use(1, "night_school", "course_home_repairs")
	K.expect(f, bool(r2["ok"]) and bool(r2.get("queued", false)) and PlaceUse.pending.has(1), "a normal visit is queued as an interaction")
	var ev_before: int = K.count_events("place_used")
	K.run(dir, 125)
	K.expect(f, K.count_events("place_used") == ev_before + 1 and not PlaceUse.pending.has(1), "and finishes after its minutes")
	K.teardown()

func _member(f: Array) -> void:
	var w := _world()
	K.set_time(5, 12)
	PlaceMember.grant(1, "school", 3)
	K.expect(f, PlaceMember.has_pass(1, "school") and PlaceMember.days_left(1, "school") == 3, "a pass lasts its days")
	K.expect(f, is_equal_approx(PlaceMember.discount(1, "school", {"pass_discount": 0.5}), 0.5) and is_equal_approx(PlaceMember.discount(1, "school", {}), 1.0), "a pass discounts only services that list it")
	K.set_time(9, 12)
	K.expect(f, not PlaceMember.has_pass(1, "school"), "and then it runs out")
	K.teardown()

func _save(f: Array) -> void:
	var w := _world()
	K.set_time(3, 19)
	PlaceUse.use(1, "night_school", "course_first_aid" if false else "course_cooking_basics", {"instant": true})
	PlaceMember.grant(1, "college", 5)
	var d: Dictionary = JSON.parse_string(JSON.stringify(LifeTick.to_dict()))
	var names: Array = PlaceStaff.names("college")
	LifeTick.from_dict(d, true)
	K.expect(f, PlaceStaff.names("college") == names, "staff survive a save and load")
	K.expect(f, EduCourses.progress(1, "cooking_basics") == 1 and PlaceMember.has_pass(1, "college"), "course progress and passes survive")
	LifeTick.from_dict({}, false)
	K.expect(f, PlaceStaff.staffed("college"), "an old save without the block starts the places fresh")
	K.teardown()
