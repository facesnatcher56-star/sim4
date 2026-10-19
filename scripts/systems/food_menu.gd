class_name FoodMenu
extends RefCounted
## Menus (task 14). A service with a `course` ("starter", "main", "dessert", "kids", "special") is a dish on a menu. Every day the kitchen picks ONE
## special per course of each place (deterministic from the day and the names, no dice, so a replay and a co-op client see the same board): the
## special is cheaper (data config.food.special_mult, 0.8) and a little more fun (special_fun). The "special" course is the chef's own dinner and
## is never discounted. Dishes that are not on a course (fast food, the bar) have no specials.
##   FoodMenu.is_special(place, service)   FoodMenu.specials(place) -> {course: service id}   FoodMenu.board(place) -> lines for the UI

static func _h(s: String) -> int:
	var h := 7
	for i in s.length():
		h = (h * 31 + s.unicode_at(i)) % 1000003
	return h

## course -> sorted service ids of the place's menu.
static func courses(pid: String) -> Dictionary:
	var out: Dictionary = {}
	var svcs: Dictionary = Places.services(pid)
	for sid in svcs:
		var c: String = str((svcs[sid] as Dictionary).get("course", ""))
		if c != "" and c != "special":
			if not out.has(c):
				out[c] = []
			(out[c] as Array).append(str(sid))
	for c2 in out:
		(out[c2] as Array).sort()
	return out

static func specials(pid: String, day: int = -1) -> Dictionary:
	if day < 0:
		day = SysUtil.day()
	var out: Dictionary = {}
	var cs: Dictionary = courses(pid)
	for c in cs:
		var ids: Array = cs[c]
		if ids.size() >= 2:                  # a course with one dish has no "special"
			out[c] = ids[(_h("%s|%s|%d" % [pid, c, day])) % ids.size()]
	return out

static func is_special(pid: String, sid: String) -> bool:
	var svc: Dictionary = Places.services(pid).get(sid, {})
	var c: String = str(svc.get("course", ""))
	if c == "" or c == "special":
		return false
	return str(specials(pid).get(c, "")) == sid

static func price_mult(pid: String, sid: String) -> float:
	return float(LifeDefs.cfg("food").get("special_mult", 0.8)) if is_special(pid, sid) else 1.0

## "Today's specials" for the UI and the news: [{course, id, label, price}].
static func board(pid: String) -> Array:
	var out: Array = []
	var sp: Dictionary = specials(pid)
	for c in ["starter", "main", "dessert"]:
		if sp.has(c):
			out.append({"course": c, "id": sp[c], "label": str(Places.services(pid)[sp[c]].get("label", sp[c])), "price": PlaceUse.price(pid, str(sp[c]))})
	return out
