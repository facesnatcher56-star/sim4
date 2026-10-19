class_name LeagueState
extends RefCounted
## The local league at the Willow Green Sports Field (task 14): four teams (data config.leagues.teams), a round-robin season of `rounds` rounds
## (two matches each), one round every Saturday, resolved at the start of Sunday. Townies fill the rosters; a resident can join a team (service
## league_join) and play the Saturday match (league_play) to strengthen it. Results are chronicle lines ("Rovers 2, Foxes 1. Mina Hale scored.");
## the champion of the season is announced (and the household of a player on the winning team cheers). Statistical for everyone but the
## residents' own membership; one dice set per week.
## Tier: TOWN, weekly. Saved in the `life` block (`league`). Uses LifeFame.rng.

static var table: Dictionary = {}         # team id -> {w, d, l, gf, ga, pts}
static var rosters: Dictionary = {}       # team id -> [townie ids]
static var members: Dictionary = {}       # resident id -> team id
static var played: Dictionary = {}        # resident id -> day of the Saturday match they played
static var round_no: int = 0
static var season: int = 1
static var results: Array = []            # the last results: [{text, day}], at most 8

const PAIRS := [[[0, 1], [2, 3]], [[0, 2], [1, 3]], [[0, 3], [1, 2]]]

static func reset() -> void:
	table.clear()
	rosters.clear()
	members.clear()
	played.clear()
	round_no = 0
	season = 1
	results.clear()

static func cfg() -> Dictionary:
	return LifeDefs.cfg("culture").get("league", {})

static func teams() -> Array:
	return LifeDefs.cfg("leagues").get("teams", [])

static func team_label(tid: String) -> String:
	for t in teams():
		if str(t["id"]) == tid:
			return str(t["label"])
	return tid

static func _fresh_table() -> void:
	table.clear()
	for t in teams():
		table[str(t["id"])] = {"w": 0, "d": 0, "l": 0, "gf": 0, "ga": 0, "pts": 0}

## Townies fill the rosters (3 a team), once they exist.
static func ensure() -> void:
	if table.is_empty():
		_fresh_table()
	if not rosters.is_empty():
		return
	var ids: Array = Story.alive_townies().filter(func(t): return Story.stage_of(t) in ["teen", "adult"]).map(func(t): return int(t["id"]))
	ids.sort()
	if ids.size() < teams().size():
		return
	var i := 0
	for t in teams():
		rosters[str(t["id"])] = []
		for _k in 3:
			if i < ids.size():
				rosters[str(t["id"])].append(ids[i])
				i += 1

static func team_of(id: int) -> String:
	return str(members.get(id, ""))

static func join(id: int) -> String:
	ensure()
	var best_team := ""
	var best_n := 999
	for t in teams():
		var n := 0
		for m in members:
			if str(members[m]) == str(t["id"]):
				n += 1
		n += (rosters.get(str(t["id"]), []) as Array).size()
		if n < best_n:
			best_n = n
			best_team = str(t["id"])
	members[id] = best_team
	return best_team

static func _strength(tid: String, day: int) -> float:
	var s := 1.0
	for t in teams():
		if str(t["id"]) == tid:
			s = float(t["strength"])
	var bonus: float = float(cfg().get("player_bonus", 0.6))
	for m in members:
		if str(members[m]) == tid and int(played.get(m, -1)) >= day - 2:
			s += bonus * clampf(float(HealthLife.meter(int(m), "fitness")) / 50.0, 0.3, 1.6) / 3.0
	return s

static func _goals(strength: float) -> int:
	var g := 0
	for _i in 4:
		if LifeFame.rng.randf() < 0.22 * strength:
			g += 1
	return g

static func _scorer(tid: String) -> String:
	var pool: Array = []
	for m in members:
		if str(members[m]) == tid:
			pool.append(LifeNote.nm(int(m)))
	for t in rosters.get(tid, []):
		pool.append(Story.name_of(int(t)))
	return "" if pool.is_empty() else str(pool[LifeFame.rng.randi_range(0, pool.size() - 1)])

## Sunday morning: the Saturday round is played.
static func on_day(day: int) -> void:
	ensure()
	if SysUtil.weekday(day - 1) != 5 or table.is_empty():
		return
	var ts: Array = teams()
	for pair in PAIRS[round_no % PAIRS.size()]:
		_match(str(ts[pair[0]]["id"]), str(ts[pair[1]]["id"]), day - 1)
	round_no += 1
	if round_no >= int(cfg().get("rounds", 3)):
		_season_end(day)
	played.clear()

static func _match(a: String, b: String, day: int) -> void:
	var ga: int = _goals(_strength(a, day))
	var gb: int = _goals(_strength(b, day))
	var ra: Dictionary = table[a]
	var rb: Dictionary = table[b]
	ra["gf"] += ga
	ra["ga"] += gb
	rb["gf"] += gb
	rb["ga"] += ga
	if ga > gb:
		ra["w"] += 1
		ra["pts"] += int(cfg().get("win_points", 3))
		rb["l"] += 1
	elif gb > ga:
		rb["w"] += 1
		rb["pts"] += int(cfg().get("win_points", 3))
		ra["l"] += 1
	else:
		ra["d"] += 1
		rb["d"] += 1
		ra["pts"] += int(cfg().get("draw_points", 1))
		rb["pts"] += int(cfg().get("draw_points", 1))
	var win: String = a if ga >= gb else b
	var scorer: String = _scorer(win) if ga != gb else ""
	var text := "%s %d, %s %d at the Sports Field.%s" % [team_label(a), ga, team_label(b), gb, "" if scorer == "" else " %s scored." % scorer]
	results.append({"text": text, "day": day})
	while results.size() > 8:
		results.pop_front()
	var subjects: Array = []
	for m in members:
		if [a, b].has(str(members[m])):
			subjects.append(int(m))
	LifeNote.say("league_result", text, subjects, 1, false)

static func standings() -> Array:
	var rows: Array = []
	for tid in table:
		var r: Dictionary = table[tid]
		rows.append({"id": tid, "label": team_label(str(tid)), "pts": int(r["pts"]), "w": int(r["w"]), "d": int(r["d"]), "l": int(r["l"]), "gd": int(r["gf"]) - int(r["ga"])})
	rows.sort_custom(func(x, y): return int(x["pts"]) > int(y["pts"]) or (int(x["pts"]) == int(y["pts"]) and int(x["gd"]) > int(y["gd"])))
	return rows

static func _season_end(_day: int) -> void:
	var st: Array = standings()
	var champ: String = str(st[0]["id"])
	var subjects: Array = []
	for m in members:
		if str(members[m]) == champ:
			subjects.append(int(m))
			var f = SysUtil.folk(int(m))
			if f != null:
				f.add_buff("cheered_up")
				LifeFame.add(int(m), 3.0)
	LifeNote.say("league_champions", "The %s won the local league (season %d) with %d points." % [team_label(champ), season, int(st[0]["pts"])], subjects, 2, true, "good")
	SysUtil.game_event("league_season_end", {"champion": champ, "season": season})
	season += 1
	round_no = 0
	_fresh_table()

static func to_dict() -> Dictionary:
	return {"table": table.duplicate(true), "rosters": rosters.duplicate(true), "members": SysUtil.str_keys(members), "played": SysUtil.str_keys(played), "round": round_no, "season": season, "results": results.duplicate(true)}

static func from_dict(d: Dictionary) -> void:
	reset()
	table = (d.get("table", {}) as Dictionary).duplicate(true)
	for t in table:
		for k in table[t]:
			table[t][k] = int(table[t][k])
	rosters = (d.get("rosters", {}) as Dictionary).duplicate(true)
	for t2 in rosters:
		rosters[t2] = SysUtil.to_ints(rosters[t2])
	for k2 in (d.get("members", {}) as Dictionary):
		members[int(str(k2))] = str(d["members"][k2])
	for k3 in (d.get("played", {}) as Dictionary):
		played[int(str(k3))] = int(d["played"][k3])
	round_no = int(d.get("round", 0))
	season = int(d.get("season", 1))
	results = (d.get("results", []) as Array).duplicate(true)
	for r in results:
		r["day"] = int(r["day"])
