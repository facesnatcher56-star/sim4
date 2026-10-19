class_name PlaceUse
extends RefCounted
## Using a service of a place (task 14): the one pipeline for every shop counter, class, doctor and ticket desk.
##   why_not(fid, pid, sid)  -> "" or a plain-word reason (closed, wrong age, not there, too poor, already done today ...)
##   price(pid, sid, fid)    -> coins (data price x the town's price index x the service's season / weekday factors x membership discount)
##   use(fid, pid, sid, opts) -> {ok, reason, price, ...}   charge up front, then the person spends `minutes` on it (an interaction "place_visit"),
##                                                            and the effects land when it ends. opts.instant = apply at once (townies, tests, hidden trips);
##                                                            opts.quiet = no toast; opts.auto = the person's own choice (PlaceAuto), not a player order.
## Effects are data (needs / buffs / skill_xp / event / text, see PlaceEffects); special services name a `handler` (PlaceHandlers).
## Tier: event driven (player commands + the interaction end). Pending visits are saved; a visit cut short refunds half.

const IID := "place_visit"

static var pending: Dictionary = {}       # folk id -> {place, service, price, minute}
static var last_used: Dictionary = {}     # "folk|service" -> day (once_per_day)
static var visits: Dictionary = {}        # place id -> visits so far (a counter for the news / tests)

static func reset() -> void:
	pending.clear()
	last_used.clear()
	visits.clear()

static func _key(fid: int, sid: String) -> String:
	return "%d|%s" % [fid, sid]

static func price(pid: String, sid: String, fid: int = -1) -> int:
	var svc: Dictionary = Places.services(pid).get(sid, {})
	var p: float = float(svc.get("price", 0))
	if p <= 0.0:
		return 0
	p *= MarketEconomy.price_mult()
	var sm: Dictionary = svc.get("season_mult", {})
	if not sm.is_empty():
		p *= float(sm.get(Seasons.current(), 1.0))
	p *= PlaceMember.discount(fid, pid, svc)
	p *= FoodMenu.price_mult(pid, sid)
	return maxi(int(round(p)), 1)

static func why_not(fid: int, pid: String, sid: String, target: int = -1) -> String:
	var svc: Dictionary = Places.services(pid).get(sid, {})
	var f = SysUtil.folk(fid)
	if svc.is_empty() or f == null:
		return "That is not available."
	var why: String = Places.place_reason(str(f.age_stage), pid)
	if why == "":
		why = Places.stage_reason(str(f.age_stage), svc)
	if why == "":
		why = Places.when_reason(svc)
	if why != "":
		return why
	if not Places.exists(pid) or not Places.is_open(pid):
		return "%s: %s." % [Places.label(pid), Places.status_text(pid)]
	if not Places.is_there(f, pid):
		return "Go to %s first." % Places.lot_label(pid)
	if pending.has(fid) or SysUtil.is_away(f):
		return "Busy right now."
	if bool(svc.get("once_per_day", false)) and int(last_used.get(_key(fid, sid), -1)) == SysUtil.day():
		return "Already done today."
	var cost: int = price(pid, sid, fid)
	if cost > 0 and not Economy.can_afford(int(f.household_id), cost):
		return "That costs %d coins." % cost
	return PlaceHandlers.check(str(svc.get("handler", "")), f, pid, sid, _with_target(svc, target))

## The service with the chosen target (a pet id ...) in `_target`, for the handlers.
static func _with_target(svc: Dictionary, target: int) -> Dictionary:
	if target < 0:
		return svc
	var s: Dictionary = svc.duplicate()
	s["_target"] = target
	return s

static func use(fid: int, pid: String, sid: String, opts: Dictionary = {}) -> Dictionary:
	var target: int = int(opts.get("target", -1))
	var why: String = why_not(fid, pid, sid, target)
	if why != "":
		return {"ok": false, "reason": why}
	var f = SysUtil.folk(fid)
	var svc: Dictionary = Places.services(pid)[sid]
	var cost: int = price(pid, sid, fid)
	var net: int = cost
	if cost > 0 and bool(svc.get("insurable", false)):
		net = maxi(cost - Incidents.insurance_cover(cost, int(f.household_id), "health"), 0)      # health insurance pays its share of doctors and therapy
	if net > 0 and not Economy.spend(int(f.household_id), net, "%s: %s" % [Places.label(pid), str(svc.get("label", sid))]):
		return {"ok": false, "reason": "That costs %d coins." % cost}
	last_used[_key(fid, sid)] = SysUtil.day()
	var minutes: float = float(svc.get("minutes", 0))
	var quiet: bool = bool(opts.get("quiet", false))           # an unplayed household: no toast for what it does (the chronicle still hears)
	var rec := {"place": pid, "service": sid, "price": cost, "minute": SysUtil.now(), "target": target, "quiet": quiet, "auto": bool(opts.get("auto", false))}
	if bool(opts.get("instant", false)) or minutes < 2.0 or not _queue(f, svc, minutes, rec):
		var res: Dictionary = finish_now(fid, pid, sid, cost, not quiet, target)
		res["price"] = cost
		return res
	pending[fid] = rec
	return {"ok": true, "reason": "", "price": cost, "queued": true}

static func _queue(f, svc: Dictionary, minutes: float, rec: Dictionary) -> bool:
	var ir := Interaction.create(IID, f, -1, not bool(rec.get("auto", false)))          # a visit the person chose themselves is not a player order (CareerShifts would call school or work "skipped")
	if ir == null:
		return false
	ir.def = ir.def.duplicate(true)
	ir.def["duration_min"] = minutes
	ir.def["label"] = Places.service_label(str(rec.get("place", "")), str(rec.get("service", ""))) if rec.has("place") else str(svc.get("label", "Visit"))
	ir.def["posture"] = str(svc.get("posture", "stand"))
	f.enqueue(ir)
	return true

## The visit ended (SystemsManager interaction hook). A cut-short visit gives half the money back and no effect.
static func on_interaction_finished(fid: int, iid: String, success: bool) -> void:
	if iid != IID or not pending.has(fid):
		return
	var rec: Dictionary = pending[fid]
	pending.erase(fid)
	if success:
		finish_now(fid, str(rec["place"]), str(rec["service"]), int(rec["price"]), not bool(rec.get("quiet", false)), int(rec.get("target", -1)))
		return
	var f = SysUtil.folk(fid)
	if f != null and int(rec["price"]) > 1:
		Economy.deposit(int(f.household_id), int(rec["price"]) / 2, "refund: %s" % Places.label(str(rec["place"])))
		SysUtil.notify("%s left early. Half the price was given back." % f.name, "info")

## Apply the effects. Public so townies, tests and hidden trips can call it.
static func finish_now(fid: int, pid: String, sid: String, paid: int = 0, announce: bool = true, target: int = -1) -> Dictionary:
	var f = SysUtil.folk(fid)
	var svc: Dictionary = Places.services(pid).get(sid, {})
	if f == null or svc.is_empty():
		return {"ok": false, "reason": "That is not available."}
	visits[pid] = int(visits.get(pid, 0)) + 1
	var out: Dictionary = PlaceEffects.apply(f, pid, sid, _with_target(svc, target), announce)
	SysUtil.game_event("place_used", {"folk_id": fid, "place": pid, "service": sid, "paid": paid})
	out["ok"] = true
	out["reason"] = ""
	return out

static func to_dict() -> Dictionary:
	return {"pending": SysUtil.str_keys(pending).duplicate(true), "used": last_used.duplicate(), "visits": visits.duplicate()}

static func from_dict(d: Dictionary) -> void:
	reset()
	pending = SysUtil.int_keys((d.get("pending", {}) as Dictionary).duplicate(true))
	last_used = {}
	for k in (d.get("used", {}) as Dictionary):
		last_used[str(k)] = int(d["used"][k])
	for k in (d.get("visits", {}) as Dictionary):
		visits[str(k)] = int(d["visits"][k])
