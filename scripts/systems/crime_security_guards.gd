class_name CrimeSecurityGuards
extends RefCounted
## Security guards (task 21): two careers (security guard, night watchman; defined in data/crimelife.json "careers" and merged into the career table at
## install time, like the justice careers) and the posts they fill. Banks, jewellers and museums have guards; a night watchman covers the closed shops.
## Townies fill the posts statistically (CrimeLifeState.guards). A guard's ALERTNESS drops when tired (night shifts, a run of them) and a guard can
## fall asleep on a night shift: an asleep guard misses almost everything. Alert guards raise detection, chase and call the police (CrimeLifeRoll).

const ROLES := ["security_guard", "night_watchman"]

static func cfg() -> Dictionary:
	return CrimeSecurity.cfg().get("guard", {})

static func install() -> void:
	var table: Dictionary = Careers.cfg()
	if table.is_empty():
		return
	var careers: Dictionary = table.get("careers", {})
	var src: Dictionary = CrimeLifeState.sect("careers")
	for cid in src:
		if not careers.has(cid):
			careers[cid] = (src[cid] as Dictionary).duplicate(true)

static func uninstall() -> void:
	var careers: Dictionary = Careers.cfg().get("careers", {})
	for cid in CrimeLifeState.sect("careers"):
		careers.erase(cid)

# ------------------------------------------------------------------ posts
## Every post that wants guards: [{post "biz:bank", guards n}] from the business security table.
static func posts() -> Array:
	var out: Array = []
	var per: Dictionary = cfg().get("per_post", {})
	for t in per:
		if int(per[t]) > 0:
			out.append({"post": "biz:%s" % t, "need": int(per[t])})
	return out

## The night watchman post covers every closed shop of the town in the small hours (one watchman, nights only).
const WATCH := "town"

static func watchman_on() -> bool:
	return is_night() and not guards_of(WATCH).is_empty()

static func is_night(h: float = -1.0) -> bool:
	var hh: float = SysUtil.hour_f() if h < 0.0 else h
	return hh >= float(cfg().get("shift_start", 20)) or hh < float(cfg().get("shift_end", 6))

## Guard ids of a post (living, not in custody).
static func guards_of(post: String) -> Array:
	var out: Array = []
	for pid in CrimeLifeState.guards:
		var g: Dictionary = CrimeLifeState.guards[pid]
		if str(g.get("post", "")) == post and CrimePerson.alive(int(pid)) and not CrimePerson.in_custody(int(pid)):
			out.append(int(pid))
	out.sort()
	return out

## Fill the posts from jobless adult townies (a few at a time). Called daily.
static func staff_town() -> void:
	var pop: Array = CrimePerson.townies_only()
	if pop.size() < int(CrimeLifeState.sect("general").get("staff_min_pop", 8)):
		return
	var rows: Array = [{"post": WATCH, "need": 1}]               # the night watchman first: one person covers every closed shop
	rows.append_array(posts())
	for row in rows:
		var have: Array = guards_of(str(row["post"]))
		var need: int = int(row["need"]) - have.size()             # alternating day / night shifts: a bank with 2 has one of each
		while need > 0:
			var pick: int = _pick_recruit()
			if pick < 0:
				break
			var night: bool = (have.size() % 2) == 1 or str(row["post"]) == WATCH
			Story.townies[pick]["career"] = "night_watchman" if night else "security_guard"
			Story.townies[pick]["level"] = 1
			CrimeLifeState.guards[pick] = {"post": str(row["post"]), "shift": "night" if night else "day", "fatigue": 0.0, "asleep_until": -1}
			have.append(pick)
			need -= 1

static func _pick_recruit() -> int:
	var best: int = -1
	var bw: float = -1.0
	for tid in CrimePerson.townies_only():
		if CrimePerson.stage(tid) != "adult" or CrimePerson.has_job(tid) or CrimePerson.has_record(tid) or CrimePerson.in_custody(tid) or CrimeLifeState.guards.has(tid) or CrimeLifePath.is_member(tid):
			continue
		var w: float = CrimeLifeState.rng.randf() + (0.3 if CrimePerson.has_trait(tid, "active") else 0.0) - (0.4 if CrimePerson.has_trait(tid, "lazy") else 0.0)
		if w > bw:
			bw = w
			best = int(tid)
	return best

# ------------------------------------------------------------------ alertness
## 0..1 how closely this guard is watching right now.
static func alertness(pid: int) -> float:
	var k: Dictionary = cfg()
	var g: Dictionary = CrimeLifeState.guards.get(pid, {})
	if g.is_empty():
		return float(k.get("base_alert", 0.8))
	if int(g.get("asleep_until", -1)) > SysUtil.now():
		return float(k.get("asleep_detect", 0.15))
	var a: float = float(k.get("base_alert", 0.8))
	if str(g.get("shift", "day")) == "night":
		a -= float(k.get("night_tired", 0.18)) + float(g.get("fatigue", 0.0))
	if CrimePerson.has_trait(pid, "lazy"):
		a += float(k.get("lazy", -0.15))
	if CrimePerson.has_trait(pid, "active"):
		a += float(k.get("active", 0.1))
	var f = CrimePerson.folk(pid)
	if f != null:
		a -= clampf((40.0 - f.get_stat_value("energy")) / 100.0, 0.0, 0.3)       # a tired player guard misses things
	return clampf(a, 0.05, 1.0)

static func is_asleep(pid: int) -> bool:
	return int(CrimeLifeState.guards.get(pid, {}).get("asleep_until", -1)) > SysUtil.now()

## How alert the watch of `scene` is right now (1.0 = a rested guard). Posts without a townie guard use an anonymous contract guard.
static func alert_for(scene: String) -> float:
	var on_shift: Array = []
	var night: bool = is_night()
	for pid in guards_of(scene):
		if (str(CrimeLifeState.guards[pid].get("shift", "day")) == "night") == night:
			on_shift.append(pid)
	if on_shift.is_empty() and night and scene.begins_with("biz:"):
		for pid3 in guards_of(WATCH):
			on_shift.append(pid3)                              # the night watchman walks the closed shops
	if on_shift.is_empty():
		return clampf(float(cfg().get("base_alert", 0.8)) - (float(cfg().get("night_tired", 0.18)) * 0.5 if night else 0.0), 0.05, 1.0)
	var total: float = 0.0
	for pid2 in on_shift:
		total += alertness(int(pid2))
	return total / float(on_shift.size())

# ------------------------------------------------------------------ the clock
static func on_hour() -> void:
	var k: Dictionary = cfg()
	var h: float = SysUtil.hour_f()
	for pid in CrimeLifeState.guards:
		var g: Dictionary = CrimeLifeState.guards[pid]
		if str(g.get("shift", "day")) != "night" or not (h >= 1.0 and h < 5.0):
			continue
		if int(g.get("asleep_until", -1)) > SysUtil.now():
			continue
		var p: float = float(k.get("asleep_base", 0.05)) + float(k.get("asleep_tired", 0.25)) * float(g.get("fatigue", 0.0)) / maxf(float(k.get("fatigue_cap", 0.3)), 0.01) * 0.3
		if CrimePerson.has_trait(int(pid), "lazy"):
			p *= 2.0
		if CrimePerson.has_trait(int(pid), "active"):
			p *= 0.5
		if CrimeLifeState.chance(p):
			g["asleep_until"] = SysUtil.now() + CrimeLifeState.rng.randi_range(40, 100)

static func on_day() -> void:
	staff_town()
	var k: Dictionary = cfg()
	for pid in CrimeLifeState.guards:
		var g: Dictionary = CrimeLifeState.guards[pid]
		if str(g.get("shift", "day")) == "night":
			g["fatigue"] = minf(float(g.get("fatigue", 0.0)) + float(k.get("fatigue_per_night", 0.04)), float(k.get("fatigue_cap", 0.3)))
		else:
			g["fatigue"] = maxf(float(g.get("fatigue", 0.0)) - 0.04, 0.0)
		if not CrimePerson.alive(int(pid)):
			CrimeLifeState.guards.erase(pid)

## Force a guard asleep or awake (tests and the casing reveal use it).
static func set_asleep(pid: int, asleep: bool) -> void:
	if CrimeLifeState.guards.has(pid):
		CrimeLifeState.guards[pid]["asleep_until"] = SysUtil.now() + 600 if asleep else -1

# ------------------------------------------------------------------ the player's shift
## Game event guard_round {folk_id}: a round of the premises. Fitness grows; sometimes a prowler is spotted and an open break-in case gets help.
static func on_round(folk_id: int) -> void:
	var f = CrimePerson.folk(folk_id)
	if f == null:
		return
	var p: float = 0.06 + 0.012 * float(f.skill_level("fitness")) + (0.05 if SysUtil.hour_f() >= 21.0 or SysUtil.hour_f() < 5.0 else 0.0)
	for c in CaseStore.in_state(["open"]):
		if str(c["kind"]) in ["burglary", "theft", "robbery"] and SysUtil.day() - int(c["day"]) <= 5 and CrimeLifeState.chance(p):
			CaseInvestigation.assist(int(c["id"]))
			SysUtil.notify("%s noticed a face that did not belong and told the police." % f.name, "good")
			CrimeLifeState.count("guard_assists")
			return
