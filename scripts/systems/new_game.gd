class_name NewGame
extends RefCounted
## Builds a fresh game world from the new-game screen's choices (UI-free, so tests run the very same code).
## NewGame.start(mgr, household, start_id, opts) -> Array of Folk.   opts: {scenario, difficulty, funds, world_seed, home_template, home_state (empty|furnished, default from data/start_home.json)} (all optional; the last two: random / drawn from the start's pool;
## without a scenario: no checklist, Normal difficulty, the start's own funds).

const SPAWN_FALLBACK := [Vector2i(6, 6), Vector2i(7, 6), Vector2i(8, 6)]

static func start(mgr: SystemsManager, h0: Dictionary, start_id: String, opts: Dictionary = {}) -> Array:
	var h: Dictionary = _one_adult(h0)          # one-character play: the player makes exactly one adult
	var w = WorldIface.world()
	for f in w.all_folk().duplicate():
		w.remove_folk(f.id)
	if w.has_method("reset"):
		w.call("reset")
	w.current_household_id = 1
	var wseed: int = int(opts.get("world_seed", -1))
	if wseed < 0:
		wseed = randi() & 0x7fffffff          # every new game draws its own lot layouts
	SimSeed.apply(wseed)                      # one master seed: the same world seed + the same commands replay the same game
	var home_tpl := str(opts.get("home_template", ""))
	if home_tpl == "" or not LotLoader.has_template(home_tpl):
		home_tpl = LotPicker.home_for(start_id, wseed)
	if home_tpl == "":
		home_tpl = str(Neighborhood.start_def(start_id).get("template", LotLoader.CLASSIC))
	Neighborhood.start_game(home_tpl, wseed)
	var home_state: String = StartHome.normalize(str(opts.get("home_state", "empty")))      # the flat is rented bare unless a test asks for the furnished house
	StartHome.apply(w, home_state)            # task 32d: the default home is bare (walls, doors, windows, floors, lights); the player furnishes it
	var spawns: Array = w.starter_spawn_tiles if w.get("starter_spawn_tiles") != null else []
	if spawns.is_empty():
		spawns = SPAWN_FALLBACK
	var folk: Array = HouseholdSetup.create_folk(h)
	if not (h0.get("folk", []) as Array).is_empty() and not (h.get("folk", []) as Array).is_empty():
		h0["folk"][0]["color"] = h["folk"][0].get("color", Color.WHITE)          # the caller (main.gd) reads the colour of the face it was handed
	var tiles: Array = HouseholdSetup.spawn_tiles(folk.size(), spawns)
	for i in folk.size():
		folk[i].household_id = 1
		w.add_folk(folk[i], tiles[i])
	var scen: Dictionary = Scenario.def(str(opts.get("scenario", "")))
	SimEnv.clock().reset(int(scen.get("start_hour", 7)) * 60)
	mgr.new_game([1])
	Players.set_player(Players.LOCAL, 1, str(h.get("name", "")))      # the players table: player 1 controls household 1
	StorytellerCmd.configure(opts.get("storyteller", StorytellerCmd.settings_args()))      # task 29: the personality chosen on the New Game screen (the host's choice applies)
	HouseholdSetup.apply(h, folk)
	if not scen.is_empty():
		_gentle_first_day()
		Scenario.begin(str(scen["id"]), str(opts.get("difficulty", Scenario.default_difficulty())))
	Neighborhood.finish_new_game(start_id, SoloCfg.start_coins())
	SoloRent.begin(Economy.primary_household())          # the studio is rented from a landlord; the first rent is due on day 8; no allowance, no free food
	SoloStart.finish(folk)
	return folk

## One-character play: only the first adult of the creator's household is used.
static func _one_adult(h: Dictionary) -> Dictionary:
	var out: Dictionary = h.duplicate(true)
	var fl: Array = out.get("folk", [])
	if fl.size() > 1:
		out["folk"] = [fl[0]]
	if not (out.get("folk", []) as Array).is_empty():
		var f0: Dictionary = out["folk"][0]
		f0["stage"] = "adult"
		f0["rel"] = "none"
	return out

## A new player's first morning should be calm: re-roll the weather seed (a few times at most) until day 1 is sunny or cloudy.
static func _gentle_first_day() -> void:
	var base: int = Weather.seed_value
	for i in 40:
		Weather.reset(base + i * 7919)
		if Weather.current() in ["sunny", "cloudy"]:
			return
