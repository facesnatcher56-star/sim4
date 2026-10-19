class_name CityElection
extends RefCounted
## Mayoral elections (task 12.4). Every term (`gov.term_days`, three game years) the town votes. Two weeks before, the candidates are fixed: the mayor (if willing),
## townies who want the job, and any player Folk who declared (`Run for Mayor`). During the campaign candidates gain support (charisma, speeches at the podium
## or the town green: `Give a Campaign Speech`). On election day every townie voter (turnout 60 percent) picks the candidate with the best score:
## charisma + support + a platform that answers the town's biggest complaint (CityMood) + a bonus for the mayor when the town is happy, a penalty when it is angry;
## the player's household votes by using `Vote for Mayor` during the campaign. The winner is mayor; a player who wins gets the politician career and the `mayor` buff.
## Tier behaviour: townie voters are counted, never simulated one by one beyond a dice roll on election day. Cadence: daily (campaign), once per term (vote).

static var phase: String = "idle"          # idle | campaign
static var vote_day: int = 0
static var candidates: Array = []          # [{id, name, platform, support, today, player, incumbent}]
static var declared: Array = []            # player folk ids who want to run
static var votes: Dictionary = {}          # str(folk id) -> index into candidates
static var last: Dictionary = {}           # the last result {day, winner, names, shares, turnout}

static func reset() -> void:
	phase = "idle"
	vote_day = 0
	candidates = []
	declared = []
	votes = {}
	last = {}

static func cfg() -> Dictionary:
	return CityGov.cfg().get("vote", {})

## The career a player politician follows (merged into the careers table by CityGov.install).
static func career_def() -> Dictionary:
	var cc: Dictionary = CityGov.cfg().get("career", {})
	return {"label": str(cc.get("label", "Politician")), "primary_skill": "charisma", "workplace": "courthouse", "days": [0, 1, 2, 3, 4],
		"hooks": {"practice_speech": 2.0, "give_campaign_speech": 3.0, "chat": 0.3}, "trait_bonus": {"charmer": 2, "shy": -2, "honest": 1},
		"levels": [
			{"title": "Party Volunteer", "start": 10, "end": 16, "pay": 12, "requires": {}},
			{"title": "Councillor", "start": 10, "end": 17, "pay": 20, "requires": {"skills": {"charisma": 2}}},
			{"title": "Deputy Mayor", "start": 9, "end": 17, "pay": 30, "requires": {"skills": {"charisma": 4}}},
			{"title": "Mayor", "start": 9, "end": 17, "pay": 44, "requires": {"skills": {"charisma": 5}}},
			{"title": "Elder Statesperson", "start": 10, "end": 16, "pay": 56, "requires": {"skills": {"charisma": 7}}}],
		"description": "Speeches, committees and the good of the town.",
		"tasks": [{"id": "give_a_speech", "label": "Practise a speech", "interactions": ["practice_speech"], "count": 1, "bonus": 5, "min_level": 1}],
		"alt_skills": [], "branches": {}}

## Townies who could stand: adults without a record who are not locked up.
static func eligible() -> Array:
	var out: Array = []
	for pid in CrimePerson.townies_only():
		if CrimePerson.stage(int(pid)) == "adult" and not CrimePerson.has_record(int(pid)) and not CrimePerson.in_custody(int(pid)):
			out.append(int(pid))
	return out

static func is_candidate(pid: int) -> bool:
	for c in candidates:
		if int(c["id"]) == pid:
			return true
	return false

static func _index_of(pid: int) -> int:
	for i in candidates.size():
		if int(candidates[i]["id"]) == pid:
			return i
	return -1

# ------------------------------------------------------------------ the player's part
static func declare(f) -> void:
	var pid: int = int(f.id)
	if not CrimePerson.is_adult(pid):
		SysUtil.notify("Only adults can stand for mayor.", "info")
		return
	if f.skill_level("charisma") < 1:
		SysUtil.notify("Nobody would vote for %s yet. Practise speaking first." % str(f.name), "info")
		return
	if declared.has(pid) or is_candidate(pid):
		SysUtil.notify("%s is already standing for mayor." % str(f.name), "info")
		return
	declared.append(pid)
	SysUtil.notify("%s will stand in the next election." % str(f.name), "good")
	if phase == "campaign":
		_add_candidate(pid, true)

static func speech(f) -> void:
	var i: int = _index_of(int(f.id))
	if phase != "campaign" or i < 0:
		SysUtil.notify("There is no campaign for %s to speak in." % str(f.name), "info")
		return
	var c: Dictionary = candidates[i]
	if int(c["today"]) >= int(cfg().get("speeches_per_day", 3)):
		SysUtil.notify("People have heard enough from %s today." % str(f.name), "info")
		return
	c["today"] = int(c["today"]) + 1
	c["support"] = float(c["support"]) + float(cfg().get("speech", 0.6)) + float(f.skill_level("charisma")) * float(cfg().get("speech_per_charisma", 0.25))
	SysUtil.notify("%s's speech went down well." % str(f.name), "good")

static func cast_vote(f) -> void:
	var pid: int = int(f.id)
	if phase != "campaign":
		SysUtil.notify("There is no election to vote in right now.", "info")
		return
	if not CrimePerson.is_adult(pid):
		SysUtil.notify("Only adults can vote.", "info")
		return
	var pick: int = best_for(pid, 0.0)
	votes[str(pid)] = pick
	SysUtil.notify("%s voted for %s." % [str(f.name), str(candidates[pick]["name"])], "good")

# ------------------------------------------------------------------ scoring
static func score(c: Dictionary) -> float:
	var s: float = CrimePerson.charisma(int(c["id"])) + float(c["support"])
	var plat: Dictionary = (CityGov.cfg().get("platforms", {}) as Dictionary).get(str(c["platform"]), {})
	if not plat.is_empty() and str(plat.get("complaint", "")) == CityMood.complaint():
		s += float(cfg().get("platform_fit", 0.6))
	if bool(c["incumbent"]):
		s += CityGov.mood_now * 1.2
	else:
		s += maxf(-CityGov.mood_now, 0.0) * 0.4
	return s

static func best_for(voter: int, noise: float) -> int:
	var best: int = 0
	var top: float = -99.0
	for i in candidates.size():
		var v: float = score(candidates[i]) + (CityState.rng.randfn(0.0, noise) if noise > 0.0 else 0.0)
		if v > top:
			top = v
			best = i
	return best

# ------------------------------------------------------------------ the clock
static func _add_candidate(pid: int, player: bool) -> void:
	if is_candidate(pid):
		return
	var keys: Array = (CityGov.cfg().get("platforms", {}) as Dictionary).keys()
	keys.sort()
	var plat: String = CityMood.complaint() if player else str(keys[CityState.rng.randi_range(0, keys.size() - 1)])
	if player:
		for k in keys:
			if str((CityGov.cfg()["platforms"][k] as Dictionary).get("complaint", "")) == plat:
				plat = str(k)
				break
		if not keys.has(plat):
			plat = "services"
	candidates.append({"id": pid, "name": CrimePerson.name_of(pid), "platform": plat, "support": 0.0, "today": 0, "player": player,
		"incumbent": int(CityGov.mayor.get("id", -1)) == pid})

static func start_campaign() -> void:
	phase = "campaign"
	vote_day = int(CityGov.mayor["term_end"])
	candidates = []
	votes = {}
	var inc: int = int(CityGov.mayor["id"])
	var inc_player: bool = bool(CityGov.mayor.get("player", false))
	if inc_player or CityState.chance(float(cfg().get("willing", 0.8))):
		_add_candidate(inc, inc_player)
	for pid in declared:
		_add_candidate(int(pid), true)
	var pool: Array = []
	for p in eligible():
		if not is_candidate(int(p)):
			pool.append([CrimePerson.charisma(int(p)) + CityState.rng.randf() * 0.5, int(p)])
	pool.sort_custom(func(a, b): return float(a[0]) > float(b[0]) or (float(a[0]) == float(b[0]) and int(a[1]) < int(b[1])))
	var want: int = maxi(int(CityGov.cfg().get("candidates", 3)) - candidates.size(), 2 - candidates.size())
	for i in mini(want, pool.size()):
		_add_candidate(int(pool[i][1]), false)
	if candidates.is_empty():
		phase = "idle"
		return
	var names: Array = []
	for c in candidates:
		names.append(str(c["name"]))
	var text: String = str(CityGov.cfg().get("texts", {}).get("campaign", "")).replace("{names}", ", ".join(names)).replace("{day}", str(vote_day))
	SysUtil.notify(text, "info")
	ChronicleHook.note("election", text, [], "", 2, true)
	declared = []

static func on_day(day: int) -> void:
	if CityGov.mayor.is_empty():
		return
	if phase == "idle":
		if day >= int(CityGov.mayor["term_end"]) - int(CityGov.cfg().get("campaign_days", 14)):
			start_campaign()
		return
	for c in candidates:
		c["today"] = 0
		if not bool(c["player"]):
			c["support"] = float(c["support"]) + CrimePerson.charisma(int(c["id"])) * 0.15 + CityState.rng.randf() * 0.1
	if day >= vote_day:
		hold()

static func hold() -> void:
	var counts: Array = []
	for i in candidates.size():
		counts.append(0)
	var noise: float = float(cfg().get("noise", 0.35))
	var turnout: float = float(cfg().get("turnout", 0.6))
	var voters: int = 0
	for pid in CrimePerson.townies_only():
		var st: String = CrimePerson.stage(int(pid))
		if (st == "adult" or st == "elder") and CityState.chance(turnout):
			counts[best_for(int(pid), noise)] += 1
			voters += 1
	for k in votes:
		if int(votes[k]) < counts.size():
			counts[int(votes[k])] += 1
			voters += 1
	var win: int = 0
	var inc_idx: int = -1
	for i2 in candidates.size():
		if bool(candidates[i2]["incumbent"]):
			inc_idx = i2
	for i3 in counts.size():
		if counts[i3] > counts[win] or (counts[i3] == counts[win] and i3 == inc_idx):
			win = i3
	_install(win, counts, voters)

static func _install(win: int, counts: Array, voters: int) -> void:
	var c: Dictionary = candidates[win]
	var again: bool = bool(c["incumbent"])
	var pct: int = int(round(float(counts[win]) / float(maxi(voters, 1)) * 100.0))
	var old: Dictionary = CityGov.mayor.duplicate()
	var text: String = str(CityGov.cfg().get("texts", {}).get("re_elected" if again else "elected", "")).replace("{name}", str(c["name"])).replace("{pct}", str(pct))
	var player: bool = bool(c["player"]) and SysUtil.folk(int(c["id"])) != null
	CityGov.mayor = {"id": int(c["id"]), "name": str(c["name"]), "since": SysUtil.day(), "term_end": SysUtil.day() + int(CityGov.cfg().get("term_days", 84)), "platform": str(c["platform"]), "player": player}
	var names: Array = []
	var shares: Array = []
	for i in candidates.size():
		names.append(str(candidates[i]["name"]))
		shares.append(counts[i])
	last = {"day": SysUtil.day(), "winner": str(c["name"]), "names": names, "votes": shares, "turnout": voters}
	phase = "idle"
	candidates = []
	votes = {}
	CityGov.hours_down_mark = int(Utilities.stats.get("hours_down", 0))
	if not again and not player:
		CityGov._apply_platform(str(c["platform"]), false)
		var plat: Dictionary = (CityGov.cfg().get("platforms", {}) as Dictionary).get(str(c["platform"]), {})
		text += " They %s." % str(plat.get("line", "promised change"))
	SysUtil.notify(text, "info" if not player else "good")
	ChronicleHook.note("election", text, [int(c["id"])], "", 3, true)
	CityGov.note("election", text)
	CityGov.council = CityPolicy.refresh_council(CityGov.council, int(c["id"]))
	if player:
		var f = SysUtil.folk(int(c["id"]))
		var lvl: int = int((CityGov.cfg().get("career", {}) as Dictionary).get("mayor_level", 4))
		if f != null and not Careers.jobs.has(int(f.id)):
			Careers.hire(f, str((CityGov.cfg().get("career", {}) as Dictionary).get("id", "politician")), lvl)
	SysUtil.game_event("mayor_elected", {"folk_id": int(c["id"]), "player": player, "again": again, "previous": int(old.get("id", -1))})

## Daily: the buff `mayor` is on the player mayor, and only on them.
static func sync_buff() -> void:
	var mid: int = int(CityGov.mayor.get("id", -1)) if bool(CityGov.mayor.get("player", false)) else -1
	for f in SysUtil.residents():
		if int(f.id) == mid:
			if not f.has_buff("mayor"):
				f.add_buff("mayor")
		elif f.has_buff("mayor"):
			f.remove_buff("mayor")

static func to_dict() -> Dictionary:
	return {"phase": phase, "vote_day": vote_day, "candidates": candidates.duplicate(true), "declared": declared.duplicate(), "votes": votes.duplicate(), "last": last.duplicate(true)}

static func from_dict(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		return
	phase = str(d.get("phase", "idle"))
	vote_day = int(d.get("vote_day", 0))
	candidates = (d.get("candidates", []) as Array).duplicate(true)
	for c in candidates:
		SysUtil.ints_in(c, ["id", "today"])
	declared = SysUtil.to_ints(d.get("declared", []))
	votes = {}
	for k in (d.get("votes", {}) as Dictionary):
		votes[str(k)] = int(d["votes"][k])
	last = (d.get("last", {}) as Dictionary).duplicate(true)
	SysUtil.ints_in(last, ["day", "turnout"])
	if last.has("votes"):
		last["votes"] = SysUtil.to_ints(last["votes"])
