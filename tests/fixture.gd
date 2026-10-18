class_name TestFixture
extends RefCounted
## Resets every piece of shared static state so each test file starts from the same world no matter what ran before it
## (or in what order). The runner calls reset() before and after each test; the kits call it from setup().

const SEED := 4242

## true in the runner's default (fast) tier: long tests shorten their simulations. false = full length (--slow, run_one).
static var fast: bool = false

## `full` normally, `quick` in the runner's fast tier: use for the length of long simulations.
static func pick(full: int, quick: int) -> int:
	return quick if fast else full

static func reset() -> void:
	Folk.reset_ids()
	SysUtil.seed_rng(SEED)
	Genetics.seed_rng(SEED)
	Autonomy.rng = null
	Autonomy.last_debug.clear()
	Loot.rng = null
	WorldIface.stub = null
	WorldIface.coins.clear()
	SystemsManager.reset_all()
	Crowd.reset()
	SocialContent.unbind()
	Weather.unforce()
	Weather.outdoors_fn = Callable()
	SaveLoad.last_error = ""
	_reset_autoloads()

## The real autoload singletons (Clock, World) are shared by every test file in the process.
static func _reset_autoloads() -> void:
	var ml := Engine.get_main_loop()
	if not (ml is SceneTree):
		return
	var root: Window = (ml as SceneTree).root
	var clk: Node = root.get_node_or_null("Clock")
	if clk != null:
		clk.reset()
		clk.speed = 1
	var wd: Node = root.get_node_or_null("World")
	if wd != null:
		for f in wd.all_folk().duplicate():
			wd.remove_folk(f.id)
		wd.reset()
		wd.current_household_id = 0
		wd.coin_spend = Callable()
		wd.coin_refund = Callable()
