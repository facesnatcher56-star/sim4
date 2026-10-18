extends RefCounted
## Shared helpers for hood_* tests (no run(), so the runner skips it). They drive the REAL autoloads (World, Clock,
## SimDirector) plus a SystemsManager, exactly like the game does.

static var mgr: SystemsManager = null
static var notes: Array = []
static var events: Array = []
static var _wired: bool = false

static func root() -> Window:
	return Engine.get_main_loop().root

static func world() -> Node:
	return root().get_node("World")

static func clock() -> Node:
	return root().get_node("Clock")

## Fresh game on the real World: lot template `start`, three folk, systems manager listening.
static func new_game(start_id: String = "classic", seed_value: int = 777) -> Array:
	SimEnv.release_standalone()
	WorldIface.stub = null
	WorldIface.coins.clear()
	if mgr != null:
		teardown()            # first: frees the previous game's systems / NPCs / map state (see teardown)
	var W: Node = world()
	for f in W.all_folk().duplicate():
		W.remove_folk(f.id)
	W.reset()
	SysUtil.seed_rng(seed_value)
	SystemsManager.reset_all()
	notes.clear()
	events.clear()
	var ev = SimEnv.events()
	if not _wired or not ev.notification.is_connected(_on_note):
		ev.notification.connect(_on_note)
		ev.game_event.connect(_on_event)
		_wired = true
	W.current_household_id = 1
	var sd: Dictionary = Neighborhood.start_def(start_id)
	Neighborhood.start_game(str(sd.get("template", "classic")))
	var folk: Array = []
	var spawns: Array = W.starter_spawn_tiles
	var i := 0
	for nm in ["Mira", "Tobin", "Wren"]:
		var f := Folk.create(nm, ["neat", "active", "social"])
		f.household_id = 1
		W.add_folk(f, spawns[i % spawns.size()])
		folk.append(f)
		i += 1
	clock().reset()
	mgr = SystemsManager.new()
	mgr.autosave_enabled = false
	mgr.setup()
	mgr.new_game([1])
	Neighborhood.finish_new_game(start_id)
	return folk

static func _on_note(t, k) -> void:
	notes.append([t, k])

static func _on_event(n, p) -> void:
	events.append([n, p])

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
	SystemsManager.reset_all()
	WorldIface.coins.clear()
	clock().reset()
	clock().speed = 1
	W.current_household_id = 0
	W.coin_spend = Callable()           # SystemsManager hooked the World's build-mode coins to the Economy
	W.coin_refund = Callable()
	TestFixture.reset()

static func set_time(day: int, hour: int, minute: int = 0) -> void:
	clock().total_minutes = (day - 1) * 1440 + hour * 60 + minute

## Advance the real clock (director + systems tick through its signals).
static func run(minutes: int) -> void:
	clock().advance_minutes(minutes)

static func has_note(fragment: String) -> bool:
	for n in notes:
		if str(n[0]).find(fragment) >= 0:
			return true
	return false

static func count_events(name: String) -> int:
	var n := 0
	for e in events:
		if e[0] == name:
			n += 1
	return n
