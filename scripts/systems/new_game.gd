class_name NewGame
extends RefCounted
## Builds a fresh game world from the new-game screen's choices (UI-free, so tests run the very same code).
## NewGame.start(mgr, household, start_id, opts) -> Array of Folk.   opts: {scenario, difficulty, funds, world_seed, home_template} (all optional; the last two: random / drawn from the start's pool;
## without a scenario: no checklist, Normal difficulty, the start's own funds).

const SPAWN_FALLBACK := [Vector2i(6, 6), Vector2i(7, 6), Vector2i(8, 6)]

static func start(mgr: SystemsManager, h: Dictionary, start_id: String, opts: Dictionary = {}) -> Array:
	var w = WorldIface.world()
	for f in w.all_folk().duplicate():
		w.remove_folk(f.id)
	if w.has_method("reset"):
		w.call("reset")
	w.current_household_id = 1
	var wseed: int = int(opts.get("world_seed", -1))
	if wseed < 0:
		wseed = randi() & 0x7fffffff          # every new game draws its own lot layouts
	var home_tpl := str(opts.get("home_template", ""))
	if home_tpl == "" or not LotLoader.has_template(home_tpl):
		home_tpl = LotPicker.home_for(start_id, wseed)
	if home_tpl == "":
		home_tpl = str(Neighborhood.start_def(start_id).get("template", LotLoader.CLASSIC))
	Neighborhood.start_game(home_tpl, wseed)
	var spawns: Array = w.starter_spawn_tiles if w.get("starter_spawn_tiles") != null else []
	if spawns.is_empty():
		spawns = SPAWN_FALLBACK
	var folk: Array = HouseholdSetup.create_folk(h)
	var tiles: Array = HouseholdSetup.spawn_tiles(folk.size(), spawns)
	for i in folk.size():
		folk[i].household_id = 1
		w.add_folk(folk[i], tiles[i])
	var scen: Dictionary = Scenario.def(str(opts.get("scenario", "")))
	SimEnv.clock().reset(int(scen.get("start_hour", 7)) * 60)
	mgr.new_game([1])
	HouseholdSetup.apply(h, folk)
	if not scen.is_empty():
		_gentle_first_day()
		Scenario.begin(str(scen["id"]), str(opts.get("difficulty", Scenario.default_difficulty())))
	Neighborhood.finish_new_game(start_id, int(opts.get("funds", -1)))
	return folk

## A new player's first morning should be calm: re-roll the weather seed (a few times at most) until day 1 is sunny or cloudy.
static func _gentle_first_day() -> void:
	var base: int = Weather.seed_value
	for i in 40:
		Weather.reset(base + i * 7919)
		if Weather.current() in ["sunny", "cloudy"]:
			return
