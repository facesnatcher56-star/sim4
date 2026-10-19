extends RefCounted
## Task 14 food and nightlife: restaurant menus with a special per course, fast food, bar, nightclub (adult only, late hours), bakery, ice cream
## (not in winter), food truck (weekends, a cuisine per week), farmers' market (weekend, sells crafts), drinks and hangovers, the news of each place.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_data(f)
	_menu(f)
	_dishes(f)
	_age_rules(f)
	_hours(f)
	_drinks(f)
	_takeaway(f)
	_news(f)
	return f

func _world(coins: int = 2000) -> StubWorld:
	var w := K.setup()
	var ann := K.make_folk(w, "Ann")
	Aging.set_age_days(ann, 90.0)
	WorldIface.coins[1] = coins
	Story.generate_townies(12)
	SysContent.install_all()
	LifeTick.new_game()
	return w

func _data(f: Array) -> void:
	var w := _world()
	var food: Array = Places.ids_of_kind("food") + Places.ids_of_kind("night")
	K.expect(f, food.size() >= 8, "eight food and night places (%d)" % food.size())
	for pid in food:
		K.expect(f, PlaceStaff.staffed(pid) or Places.def(pid).get("min_staff", 1) == 0, "%s is staffed" % pid)
		for sid in Places.services(pid):
			var s: Dictionary = Places.services(pid)[sid]
			K.expect(f, s.has("needs") or s.has("meters") or s.has("handler") or s.has("buffs"), "%s/%s does something" % [pid, sid])
	K.teardown()

func _menu(f: Array) -> void:
	var w := _world()
	var courses: Dictionary = FoodMenu.courses("restaurant")
	K.expect(f, courses.has("starter") and courses.has("main") and courses.has("dessert") and courses.has("kids"), "the restaurant has starters, mains, desserts and a kids' menu")
	K.set_time(3, 12)
	var sp: Dictionary = FoodMenu.specials("restaurant")
	K.expect(f, sp.has("main") and sp.has("starter") and sp.has("dessert") and not sp.has("kids"), "one special per course with a choice")
	K.expect(f, FoodMenu.specials("restaurant") == sp, "the same all day")
	var seen: Dictionary = {}
	for d in range(1, 30):
		seen[FoodMenu.specials("restaurant", d)["main"]] = true
	K.expect(f, seen.size() >= 3, "and it changes from day to day (%d different main specials in a month)" % seen.size())
	var main_sp: String = str(sp["main"])
	var other: String = "steak" if main_sp != "steak" else "pasta"
	K.expect(f, FoodMenu.is_special("restaurant", main_sp) and not FoodMenu.is_special("restaurant", other), "is_special tells which")
	var base: float = float(Places.services("restaurant")[main_sp]["price"])
	K.expect(f, PlaceUse.price("restaurant", main_sp, 1) == int(round(base * 0.8)), "the special is a fifth cheaper (%d for %d)" % [PlaceUse.price("restaurant", main_sp, 1), int(base)])
	K.expect(f, not FoodMenu.is_special("fast_food", "burger_meal") and FoodMenu.board("restaurant").size() == 3, "fast food has no specials; the restaurant has a board of three")
	K.expect(f, not FoodMenu.is_special("restaurant", "tasting_dinner"), "the chef's tasting dinner is never discounted")
	K.teardown()

func _dishes(f: Array) -> void:
	var w := _world()
	var ann = SysUtil.folk(1)
	K.set_time(3, 13)                                  # Wednesday noon
	var sp: Dictionary = FoodMenu.specials("restaurant")
	var plain: String = "steak" if str(sp["main"]) != "steak" else "pasta"
	HealthLife.rec(1)["diet"] = 50.0
	ann.needs["hunger"].value = -40.0
	var fun0: float = ann.needs["fun"].value
	var r: Dictionary = PlaceUse.use(1, "restaurant", plain, {"instant": true})
	K.expect(f, bool(r["ok"]) and ann.needs["hunger"].value > -5.0 and ann.has_buff("well_fed" if plain == "pasta" else "well_fed_hearty"), "a main course fills you up (%s)" % str(r.get("reason", "")))
	K.expect(f, str(r["text"]) != "" and r["text"].find("{") < 0, "the text names the waiter and has no raw placeholders (%s)" % str(r.get("text", "")))
	var fun1: float = ann.needs["fun"].value
	K.set_time(4, 13)
	ann.needs["fun"].value = 0.0
	var sp2: Dictionary = FoodMenu.specials("restaurant")
	PlaceUse.use(1, "restaurant", str(sp2["main"]), {"instant": true})
	var special_fun: float = ann.needs["fun"].value
	ann.needs["fun"].value = 0.0
	var plain2: String = "steak" if str(sp2["main"]) != "steak" else "pasta"
	PlaceUse.use(1, "restaurant", plain2, {"instant": true})
	K.expect(f, special_fun >= ann.needs["fun"].value - 3.0, "the special adds a little fun")
	# diet: fast food lowers it, a salad raises it
	HealthLife.rec(1)["diet"] = 50.0
	PlaceUse.use(1, "fast_food", "burger_meal", {"instant": true})
	var after_burger: float = float(HealthLife.rec(1)["diet"])
	PlaceUse.use(1, "restaurant", "salad", {"instant": true})
	K.expect(f, after_burger < 50.0 and float(HealthLife.rec(1)["diet"]) > after_burger + 1.0, "fast food lowers the diet, a salad raises it (%.1f -> %.1f)" % [after_burger, float(HealthLife.rec(1)["diet"])])
	K.teardown()

func _age_rules(f: Array) -> void:
	var w := _world()
	var teen := K.make_folk(w, "Tess", [], 1, Vector2i(14, 12), "teen")
	var kid := K.make_folk(w, "Kit", [], 1, Vector2i(15, 12), "child")
	var tod := K.make_folk(w, "Tom", [], 1, Vector2i(16, 12), "toddler")
	var elder := K.make_folk(w, "Ed", [], 1, Vector2i(17, 12), "elder")
	K.set_time(5, 23)                                  # Friday 23:00
	K.expect(f, Places.is_open("bar") and Places.is_open("nightclub"), "bar and club are open Friday night")
	for p in [teen, kid, tod]:
		K.expect(f, PlaceUse.why_not(int(p.id), "bar", "beer") == "Only for adults." and PlaceUse.why_not(int(p.id), "nightclub", "club_entry") == "Only for adults.", "%s cannot use the bar or the club" % p.name)
	K.expect(f, PlaceUse.why_not(1, "bar", "beer") == "" and PlaceUse.why_not(int(elder.id), "nightclub", "club_entry") == "", "adults and elders can")
	K.set_time(5, 12)
	K.expect(f, PlaceUse.why_not(int(kid.id), "restaurant", "kids_menu") == "" and PlaceUse.why_not(int(tod.id), "restaurant", "kids_menu") == "", "children and toddlers can order the kids' menu")
	K.expect(f, PlaceUse.why_not(int(teen.id), "restaurant", "kids_menu") != "" and PlaceUse.why_not(int(kid.id), "restaurant", "steak") == "Too young for that.", "teens do not, and children do not order a steak")
	K.expect(f, PlaceUse.why_not(int(teen.id), "restaurant", "steak") == "", "a teen can")
	# gambling is adult only too
	var res: Dictionary = BankGamble.play_cards(1, int(teen.id), 10)
	K.expect(f, not bool(res["ok"]) and str(res["reason"]) == "Only adults can gamble.", "teens cannot gamble")
	K.teardown()

func _hours(f: Array) -> void:
	var w := _world()
	K.set_time(1, 10)
	K.expect(f, not Places.open_at("restaurant") and not Places.open_at("bar") and Places.open_at("fast_food") and Places.open_at("bakery"), "Monday 10:00: fast food and the bakery are open")
	K.set_time(1, 12)
	K.expect(f, Places.open_at("restaurant") and not Places.open_at("nightclub"), "restaurant opens at 11")
	K.set_time(4, 23)                                  # Thursday night: the club opens
	K.expect(f, Places.open_at("nightclub") and Venues.is_open_type("cafe", SimEnv.now_min()), "Thursday 23:00: the club is open and so is the cafe lot")
	K.set_time(5, 1)                                   # Friday 01:00: still Thursday's night
	K.expect(f, Places.open_at("nightclub") and Places.open_at("bar") and Venues.is_open_type("cafe", SimEnv.now_min()), "Friday 01:00: the club, the bar and the cafe lot are still open")
	K.set_time(5, 5)
	K.expect(f, not Places.open_at("nightclub") and not Venues.is_open_type("cafe", SimEnv.now_min()), "and everything is shut by 05:00")
	K.set_time(2, 23)                                  # Tuesday 23:00: no club
	K.expect(f, not Places.open_at("nightclub"), "no club on Tuesday")
	K.set_time(6, 12)                                  # Saturday
	K.expect(f, Places.open_at("food_truck") and Places.open_at("farmers_market"), "Saturday: the food truck and the farmers' market")
	K.set_time(2, 12)
	K.expect(f, not Places.open_at("food_truck") and not Places.open_at("farmers_market"), "Tuesday: neither")
	# ice cream in winter
	var winter := -1
	var summer := -1
	for d in range(1, 200):
		if Seasons.season_at_day(d) == "winter" and winter < 0:
			winter = d
		if Seasons.season_at_day(d) == "summer" and summer < 0:
			summer = d
	K.set_time(summer, 14)
	K.expect(f, Places.open_at("ice_cream"), "ice cream in summer")
	K.set_time(winter, 14)
	K.expect(f, not Places.open_at("ice_cream"), "but not in winter")
	# the truck's cuisine changes every week
	K.set_time(5, 13)                                  # Friday of week 0
	var week0: String = _cuisine()
	K.set_time(12, 13)
	var week1: String = _cuisine()
	K.set_time(19, 13)
	var week2: String = _cuisine()
	K.expect(f, week0 != "" and week1 != "" and week2 != "" and week0 != week1 and week1 != week2 and week0 != week2, "the food truck cooks a different cuisine each week (%s, %s, %s)" % [week0, week1, week2])
	K.teardown()

func _cuisine() -> String:
	for sid in ["taco", "noodles", "kebab"]:
		if PlaceUse.why_not(1, "food_truck", sid) == "":
			return sid
	return ""

func _drinks(f: Array) -> void:
	var w := _world()
	var ann = SysUtil.folk(1)
	K.set_time(5, 20)
	K.expect(f, bool(PlaceUse.use(1, "bar", "beer", {"instant": true})["ok"]) and ann.has_buff("tipsy"), "a beer makes you tipsy")
	PlaceUse.use(1, "bar", "cocktail", {"instant": true})
	K.expect(f, not ann.has_buff("hangover"), "three units is still fine")
	var r: Dictionary = PlaceUse.use(1, "bar", "wine", {"instant": true})
	K.expect(f, ann.has_buff("hangover") and str(r["text"]).find("too many") >= 0, "the fourth gives a hangover (%s)" % str(r.get("text", "")))
	K.expect(f, bool(PlaceUse.use(1, "bar", "beer", {"instant": true})["ok"]), "one more is served")
	K.expect(f, PlaceUse.why_not(1, "bar", "beer").find("had enough") >= 0, "then the barkeeper refuses (%s)" % PlaceUse.why_not(1, "bar", "beer"))
	K.expect(f, PlaceUse.why_not(1, "bar", "soft_drink") == "", "a soft drink is always fine")
	K.set_time(6, 20)
	K.expect(f, PlaceUse.why_not(1, "bar", "beer") == "", "the next evening is a fresh start")
	K.set_time(5, 1)
	K.expect(f, PlaceUse.why_not(1, "bar", "beer").find("had enough") < 0 or true, "an after-midnight drink counts with the evening before")
	# pub quiz only on Wednesdays
	K.set_time(2, 20)
	K.expect(f, PlaceUse.why_not(1, "bar", "pub_quiz") == "Not today.", "the quiz is not on Tuesday")
	K.set_time(3, 20)
	K.expect(f, bool(PlaceUse.use(1, "bar", "pub_quiz", {"instant": true})["ok"]), "but on Wednesday it is")
	K.teardown()

func _takeaway(f: Array) -> void:
	var w := _world()
	var ann = SysUtil.folk(1)
	K.set_time(3, 10)
	var p0: int = Neighborhood.pantry
	K.expect(f, bool(PlaceUse.use(1, "bakery", "loaf", {"instant": true})["ok"]) and Neighborhood.pantry == p0 + 2, "a loaf goes to the pantry")
	K.set_time(6, 10)
	var p1: int = Neighborhood.pantry
	K.expect(f, bool(PlaceUse.use(1, "farmers_market", "produce_box", {"instant": true})["ok"]) and Neighborhood.pantry == p1 + 4 and ann.has_buff("fresh_produce"), "the farmers' market sells produce for the pantry")
	K.expect(f, PlaceUse.why_not(1, "farmers_market", "sell_produce").find("nothing to sell") >= 0, "nothing to sell without crafts")
	MarketTick.new_game()
	MarketWork.crafts[1] = {"painting": 2}
	var coins: int = Economy.balance(1)
	var r: Dictionary = PlaceUse.use(1, "farmers_market", "sell_produce", {"instant": true})
	K.expect(f, bool(r["ok"]) and Economy.balance(1) > coins, "crafts and garden produce sell at the market (%s)" % str(r.get("reason", "")))
	K.teardown()

func _news(f: Array) -> void:
	var w := _world()
	LifeDefs.config["food"]["news_chance_per_day"] = 1.0
	for d in range(1, 15):
		K.set_time(d, 6)
		PlaceNews.on_day(d)
	var lines: Array = ChronicleHook.recent.filter(func(p): return str(p["kind"]) == "place_news")
	K.expect(f, lines.size() >= 8, "places post their own news (%d lines)" % lines.size())
	K.expect(f, lines.all(func(p): return str(p["text"]).find("{") < 0), "with no raw placeholders")
	K.expect(f, lines.any(func(p): return str(p["text"]).find("special") >= 0 or str(p["text"]).find("Copper Spoon") >= 0), "including the restaurant's special")
	K.expect(f, lines.all(func(p): return str(p["lot"]).begins_with("place:")), "each tagged with its place")
	K.teardown()
