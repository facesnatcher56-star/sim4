class_name HealthCollapse
extends RefCounted
## "Collapsed": the person lies down where they are (emergency interaction `collapse_floor`, buff `collapsed`) and cannot act.
## Ways out: a housemate helps (`help_collapsed`, started on their own after a short delay), a doctor call, the hospital, or - for
## exhaustion - simply sleeping it off. Kinds: hunger | exhaustion | cold | heat.

const IID := "collapse_floor"
const HELP_IID := "help_collapsed"

static func collapse(f, kind: String) -> bool:
	if f == null or Health.is_collapsed(f):
		return false
	var r: Dictionary = Health.rec_of(int(f.id))
	r["collapse"] = kind
	r["collapse_min"] = SysUtil.now()
	r["help_try"] = SysUtil.now() + int(Health.cfg("rescue").get("delay_min", 20))
	f.add_buff("collapsed")
	f.cancel_current("collapsed")
	f.clear_queue()
	var ir := Interaction.create(IID, f, -1, false)
	if ir != null:
		f.enqueue(ir)
	Health.count("collapse_" + kind)
	Health.tell(f, "collapsed_" + kind, "bad")
	SysUtil.game_event("health_collapsed", {"folk_id": int(f.id), "kind": kind})
	ChronicleHook.note("collapse", Health.text("collapsed_" + kind, f), [int(f.id)], "home:%d" % int(f.household_id), 3, false)
	return true

static func kind_of(f) -> String:
	return str(Health.rec_of(int(f.id)).get("collapse", "")) if Health.is_collapsed(f) else ""

## End the collapse without any side effect (the caller decides what the person gets).
static func clear(f) -> void:
	var r: Dictionary = Health.rec_of(int(f.id))
	r.erase("collapse")
	r.erase("collapse_min")
	r.erase("help_try")
	f.remove_buff("collapsed")
	if f.current != null and f.current.def_id == IID:
		f.current.cancel("rescued")
	for q in f.queue.duplicate():
		if (q as Interaction).def_id == IID:
			f.queue.erase(q)

## Bring them round. The cause that put them there is eased but not erased, so a freezing person is still cold and shaky.
static func rescue(f, helper = null) -> bool:
	if f == null or not Health.is_collapsed(f):
		return false
	var kind: String = kind_of(f)
	var r: Dictionary = Health.rec_of(int(f.id))
	var rc: Dictionary = Health.cfg("rescue")
	clear(f)
	match kind:
		"hunger":
			_raise(f, "hunger", float(rc.get("hunger_to", 15)))
			r["hunger_min"] = 0.0
			r.erase("w_hunger")
			f.remove_buff("weak_hunger")
		"exhaustion":
			_raise(f, "energy", float(rc.get("energy_to", -30)))
			r["energy_min"] = 0.0
		"cold":
			r["cold_min"] = HealthExposure.stage_min("cold", 2) * 0.6
			f.add_buff("bundled_up")
		"heat":
			r["heat_min"] = HealthExposure.stage_min("heat", 2) * 0.6
			f.add_buff("cooled_down")
	f.add_buff("shaky")
	Health.count("rescue_" + kind)
	if helper != null:
		SysUtil.notify("%s helped %s back on their feet." % [helper.name, f.name], "good")
	else:
		SysUtil.notify("%s is back on their feet." % f.name, "good")
	SysUtil.game_event("health_rescued", {"folk_id": int(f.id), "kind": kind, "helper": int(helper.id) if helper != null else -1})
	return true

static func _raise(f, need: String, to: float) -> void:
	var cur: float = f.get_stat_value(need)
	if cur < to:
		f.add_to_stat(need, to - cur)

# ------------------------------------------------------------------ per minute
static func tick(f, r: Dictionary, now: int) -> void:
	if not Health.is_collapsed(f):
		return
	var kind: String = str(r.get("collapse", ""))
	if kind == "exhaustion":
		f.add_to_stat("energy", float(Health.cfg("rescue").get("sleep_energy_per_min", 0.5)))
		if f.get_stat_value("energy") >= float(Health.cfg("rescue").get("wake_energy", -20)):
			clear(f)
			f.add_buff("shaky")
			Health.tell(f, "woke_up", "info")
			return
	if kind == "":
		kind = "hunger"           # a collapse restored from an older save
		r["collapse"] = kind
	if int(r.get("help_try", 0)) <= now:
		r["help_try"] = now + 10
		_auto_help(f)
	_town_help(f, r, now, kind)

## Nobody stays collapsed for days: if no housemate helped, passers-by / the town call an ambulance after a few hours (children sooner or
## later per `dependent_hospital_min`). They are brought round and taken to hospital (rescue also lifts the needs off the floor).
static func _town_help(f, r: Dictionary, now: int, kind: String) -> void:
	var rc: Dictionary = Health.cfg("rescue")
	var wait: int = int(rc.get("town_help_min", 240))
	if (rc.get("dependent_stages", []) as Array).has(str(f.age_stage)):
		wait = int(rc.get("dependent_hospital_min", 360))
	if now - int(r.get("collapse_min", now)) < wait:
		return
	rescue(f, null)
	Hospital.admit(int(f.id), 2, "neglect")
	SysUtil.game_event("neglect_emergency", {"folk_id": int(f.id), "kind": kind})
	Health.count("neglect_emergency")

## Send the nearest capable housemate to help.
static func _auto_help(f) -> void:
	if not bool(Health.cfg("rescue").get("auto_help", true)):
		return
	var best = null
	var best_d: int = 1 << 30
	for h in SysUtil.residents():
		if int(h.household_id) != int(f.household_id) or int(h.id) == int(f.id) or Health.is_collapsed(h) or SysUtil.is_away(h) or Hospital.is_in(h):
			continue
		if not (str(h.age_stage) in ["teen", "adult", "elder"]) or _already_helping(h, f):
			continue
		var d: int = absi(h.tile.x - f.tile.x) + absi(h.tile.y - f.tile.y)
		if d < best_d:
			best_d = d
			best = h
	if best == null:
		return
	var ir := Interaction.create(HELP_IID, best, int(f.id), false)
	if ir != null and ir.can_run(best, null, false):
		best.enqueue(ir)
		Health.count("auto_help")

static func _already_helping(h, f) -> bool:
	if h.current != null and h.current.def_id == HELP_IID and int(h.current.target_id) == int(f.id):
		return true
	for q in h.queue:
		if (q as Interaction).def_id == HELP_IID and int((q as Interaction).target_id) == int(f.id):
			return true
	return false
