class_name TestFixture
extends RefCounted
## Resets every piece of shared static state so each test file starts from the same world no matter what ran before it
## (or in what order). The runner calls reset() before and after each test; the kits call it from setup().

const SEED := 4242

## Wall-clock budgets in tests are multiplied by this: they only catch a return of the old (10x+) behaviour, never a busy machine.
## Load-independent checks (counts of path queries, A* runs) are preferred where a test can count.
const SLACK := 5.0

## true in the runner's default (fast) tier: long tests shorten their simulations. false = full length (--slow, run_one).
static var fast: bool = false

## `full` normally, `quick` in the runner's fast tier: use for the length of long simulations.
static func pick(full: int, quick: int) -> int:
	return quick if fast else full

static func reset() -> void:
	Folk.reset_ids()
	SimSeed.apply(SEED)                 # global rng + SysUtil + Genetics + Autonomy + Loot: every test starts from the same random streams
	Autonomy.last_debug.clear()
	Autonomy.full_debug = true          # tests may inspect a row for every candidate (the game keeps only the useful ones)
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
## The runners (run_all / run_one) call this once: settings, UI flags and save slots of a TEST process live in a private folder.
## Without it parallel shards (tools/run_fast.ps1) and the player's own files shared user://settings.cfg and user://saves: a test that
## sets "surprises" to chaotic/rare, or writes slot 95/97, changed the dice of whatever other shard happened to load it at that moment.
static func isolate_user_files() -> void:
	var dir := "user://test_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(dir + "/saves")
	GameSettings.path = dir + "/settings.cfg"
	GameSettings.values = {}
	UIPrefs.PATH = dir + "/ui_prefs.cfg"
	SaveLoad.DIR = dir + "/saves"
	ShareState.seen_path = dir + "/share_seen.json"
	_isolated_dir = dir

static var _isolated_dir: String = ""

## Best-effort removal of the private folder at the end of a run.
static func clean_user_files() -> void:
	if _isolated_dir == "":
		return
	var stack: Array = [_isolated_dir]
	var dirs: Array = []
	while not stack.is_empty():
		var d: String = stack.pop_back()
		dirs.append(d)
		for s in DirAccess.get_directories_at(d):
			stack.append(d + "/" + s)
		for fl in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(d + "/" + fl)
	dirs.reverse()
	for d in dirs:
		DirAccess.remove_absolute(d)
	_isolated_dir = ""
