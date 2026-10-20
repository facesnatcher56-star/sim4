extends RefCounted
## Shared helpers for start_* tests (no run(), so the runner skips it): the REAL new-game code path (NewGame.start) on the real
## World / Clock / SimDirector with a SystemsManager listening, exactly like main.gd, minus the UI.

static var mgr: SystemsManager = null

static func root() -> Window:
	return Engine.get_main_loop().root

static func world() -> Node:
	return root().get_node("World")

static func clock() -> Node:
	return root().get_node("Clock")

## Start `scenario_id` (preset household) at `diff`. `h` replaces the generated household (custom play).
static func new_game(scenario_id: String, diff: String = "normal", h: Dictionary = {}, funds_base: int = -1, extra: Dictionary = {}) -> Array:
	SimEnv.release_standalone()
	WorldIface.stub = null
	WorldIface.coins.clear()
	if mgr != null:
		teardown()
	TestFixture.reset()
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var def: Dictionary = Scenario.def(scenario_id)
	if h.is_empty():
		h = HouseholdSetup.make_household(scenario_id, rng)
	mgr = SystemsManager.new()
	mgr.autosave_enabled = false
	mgr.setup()
	var opts := {"scenario": scenario_id, "difficulty": diff, "funds": Scenario.funds_for(scenario_id, diff, funds_base), "home_state": "furnished"}      # the old furnished start; start_empty_test passes "empty"
	opts.merge(extra, true)      # e.g. world_seed, home_template
	return NewGame.start(mgr, h, str(def.get("start_id", "classic")), opts)

static func teardown() -> void:
	if mgr != null:
		mgr.teardown()
		mgr.free()
		mgr = null
	var W: Node = world()
	for f in W.all_folk().duplicate():
		f.current = null
		f.queue.clear()
		W.remove_folk(f.id)
	W.reset()
	W.current_household_id = 0
	W.coin_spend = Callable()
	W.coin_refund = Callable()
	TestFixture.reset()

static func run(minutes: int) -> void:
	clock().advance_minutes(minutes)
