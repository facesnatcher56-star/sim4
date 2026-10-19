extends RefCounted
## Determinism (multiplayer-ready rule 24A.2): the same seed twice, a new game, the same commands => the identical state hash after N game
## days: CoopHash.of_world() PLUS a hash of the Chronicle / Story state PLUS a hash of every saved system block. A different seed must differ
## (the hash is sensitive). The fast tier plays 8 hours across a midnight (hour + day jobs); determinism_longrun_test.gd plays 3 days.

const HoodKit := preload("res://tests/hood_kit.gd")
var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

## Minutes to play and the clock to start at (day, hour).
func _plan() -> Array:
	return [TestFixture.pick(3 * 1440, 8 * 60), 1, 16 if TestFixture.fast else 7]

static func story_hash() -> String:
	return JSON.stringify([ChronicleHook.recent, Story.to_dict()], "", true).sha256_text().substr(0, 16)

static func systems_hash() -> String:
	return JSON.stringify(SaveLoad.snapshot("d")["systems"], "", true).sha256_text().substr(0, 16)

## New game from `seed_value`, `cmd` (Callable or null) after the first hour, `minutes` of play. Returns the three hashes.
func play(seed_value: int, minutes: int, start_day: int, start_hour: int, with_commands: bool) -> Dictionary:
	HoodKit.teardown()                 # a clean start whatever ran before ...
	SimSeed.apply(seed_value)          # ... then every random stream from the one master seed
	var folk: Array = HoodKit.new_game("classic", seed_value, seed_value)
	HoodKit.set_time(start_day, start_hour)
	HoodKit.run(60)
	if with_commands:
		Commands.run({"folk_id": int(folk[0].id), "action": "career_skip"})
		Commands.run({"folk_id": int(folk[1].id), "action": "interact", "args": {"interaction_id": "sleep", "target_id": -1}})
	HoodKit.run(minutes - 60)
	var out := {"world": CoopHash.of_world(), "story": story_hash(), "systems": systems_hash(), "min": SimEnv.now_min()}
	HoodKit.teardown()
	return out

## A third game of the first seed AFTER a game of another seed: catches caches / statics keyed so that a later game reads an earlier game's data
## (the WeatherWorld rain index did, see weather_rain_cache_test.gd). Costs one more play, so the 3-day slow variant switches it off.
func _replay_after_other_seed() -> bool:
	return true

func run() -> Array:
	fails = []
	var p := _plan()
	var a := play(555, int(p[0]), int(p[1]), int(p[2]), true)
	var b := play(555, int(p[0]), int(p[1]), int(p[2]), true)
	for k in ["world", "story", "systems", "min"]:
		_check(a[k] == b[k], "same seed twice, same commands: %s differs (%s vs %s)" % [k, str(a[k]), str(b[k])])
	var c := play(556, int(p[0]), int(p[1]), int(p[2]), true)
	_check(c["world"] != a["world"] or c["systems"] != a["systems"], "a different seed gives a different state (the hash is sensitive)")
	if _replay_after_other_seed():
		var d := play(555, int(p[0]), int(p[1]), int(p[2]), true)
		for k in ["world", "story", "systems", "min"]:
			_check(a[k] == d[k], "same seed after a game of another seed: %s differs (%s vs %s)" % [k, str(a[k]), str(d[k])])
	return fails
