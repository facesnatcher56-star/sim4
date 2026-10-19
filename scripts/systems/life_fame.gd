class_name LifeFame
extends RefCounted
## Fame, high scores and a stream of luck for the culture and leisure places (task 14).
##   fame      grows when somebody performs, exhibits or wins and fades slowly (x0.985 a day); "unknown" .. "a local star"
##   records   the town's best score of each game (bowling, arcade) with the name and day; a new record goes to the chronicle
##   best      each person's own best score
## Own seeded rng (performances, scores, league matches). Saved in the `life` block (`culture`).

const SEED := 140071

static var fame: Dictionary = {}          # person id -> float
static var records: Dictionary = {}       # game -> {score, name, day}
static var best: Dictionary = {}          # person id -> {game: score}
static var rng: RandomNumberGenerator = RandomNumberGenerator.new()

static func reset() -> void:
	fame.clear()
	records.clear()
	best.clear()
	rng = RandomNumberGenerator.new()
	rng.seed = SEED

static func cfg() -> Dictionary:
	return LifeDefs.cfg("culture")

static func value(id: int) -> float:
	return float(fame.get(id, 0.0))

static func add(id: int, n: float) -> void:
	fame[id] = minf(value(id) + n, 100.0)

static func label(id: int) -> String:
	var v: float = value(id)
	if v >= 40.0:
		return "a local star"
	if v >= 15.0:
		return "well known in town"
	if v >= 4.0:
		return "starting to be noticed"
	return "unknown"

## A score for `game`: updates the person's best and the town record. Returns {score, record: bool, personal: bool}.
static func note_score(id: int, game: String, score: int, name: String) -> Dictionary:
	var mine: Dictionary = best.get(id, {})
	var personal: bool = score > int(mine.get(game, 0))
	if personal:
		mine[game] = score
		best[id] = mine
	var rec: Dictionary = records.get(game, {})
	var is_record: bool = score > int(rec.get("score", 0))
	if is_record:
		records[game] = {"score": score, "name": name, "day": SysUtil.day()}
	return {"score": score, "record": is_record, "personal": personal}

static func on_day(_day: int) -> void:
	var decay: float = float(cfg().get("fame_decay", 0.985))
	for id in fame.keys():
		fame[id] = float(fame[id]) * decay
		if float(fame[id]) < 0.2:
			fame.erase(id)

static func to_dict() -> Dictionary:
	return {"fame": SysUtil.str_keys(fame), "records": records.duplicate(true), "best": SysUtil.str_keys(best).duplicate(true), "rng_state": str(rng.state)}

static func from_dict(d: Dictionary) -> void:
	reset()
	for k in (d.get("fame", {}) as Dictionary):
		fame[int(str(k))] = float(d["fame"][k])
	records = (d.get("records", {}) as Dictionary).duplicate(true)
	for g in records:
		records[g]["score"] = int(records[g]["score"])
		records[g]["day"] = int(records[g]["day"])
	for k2 in (d.get("best", {}) as Dictionary):
		var b: Dictionary = {}
		for g2 in d["best"][k2]:
			b[str(g2)] = int(d["best"][k2][g2])
		best[int(str(k2))] = b
	if d.has("rng_state"):
		rng.state = int(str(d["rng_state"]))
