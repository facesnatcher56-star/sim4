class_name PlaceHandlers
extends RefCounted
## The code behind services that are more than needs and buffs (task 14). A service names `"handler": "<name>"` (+ `args`); this is the one
## dispatch table: check() may refuse before anything is charged, finish() runs when the visit ends. Each area owns a group of handler names and
## one class that implements them; a new area adds its group here.

const EDU := ["lecture", "course", "enrol_preschool", "tutor"]
const HEALTH := ["checkup", "treat", "vaccinate", "dental_clean", "dental_fix", "counsel", "prescription"]
const FOOD := ["drink", "pantry", "sell_crafts"]
const LEISURE := ["perform", "exhibit", "score", "league_join", "league_play", "league_watch", "club_join", "club_meet"]

static func known(handler: String) -> bool:
	return EDU.has(handler) or HEALTH.has(handler) or FOOD.has(handler) or LEISURE.has(handler)

static func check(handler: String, f, pid: String, sid: String, svc: Dictionary) -> String:
	if EDU.has(handler):
		return EduServices.check(handler, f, pid, sid, svc)
	if HEALTH.has(handler):
		return HealthServices.check(handler, f, pid, sid, svc)
	if FOOD.has(handler):
		return FoodServices.check(handler, f, pid, sid, svc)
	if LEISURE.has(handler):
		return LeisureServices.check(handler, f, pid, sid, svc)
	return ""

static func finish(handler: String, f, pid: String, sid: String, svc: Dictionary) -> Dictionary:
	if EDU.has(handler):
		return EduServices.finish(handler, f, pid, sid, svc)
	if HEALTH.has(handler):
		return HealthServices.finish(handler, f, pid, sid, svc)
	if FOOD.has(handler):
		return FoodServices.finish(handler, f, pid, sid, svc)
	if LEISURE.has(handler):
		return LeisureServices.finish(handler, f, pid, sid, svc)
	return {}
