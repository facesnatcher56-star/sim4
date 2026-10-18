extends RefCounted
## Shared helpers for social_* tests (no run() method, so the runner skips it).

const K = preload("res://tests/systems_kit.gd")
const CK = preload("res://tests/content_kit.gd")

static var _saved_next_id: int = -1

static func setup(seed_value: int = 777) -> StubWorld:
	_saved_next_id = Folk._next_id      # the social tests create lots of folk: do not leak the id counter into the townie range
	var w: StubWorld = K.setup(seed_value)
	SysUtil.seed_rng(seed_value)
	SocialContent.install()
	return w

static var _dir = null

static func teardown() -> void:
	SocialContent.unbind()
	_dir = null
	K.teardown()
	if _saved_next_id >= 0:
		Folk._next_id = _saved_next_id

static func folk(w: StubWorld, fname: String, traits: Array = [], tile: Vector2i = Vector2i(12, 12), hid: int = 1) -> Folk:
	var f := K.make_folk(w, fname, traits, hid, tile)
	return f

## Run one interaction from `a` onto `b` to its end (player command, tests ignored). Returns the Interaction.
static func run(a: Folk, b: Folk, iid: String, minutes_cap: int = 600) -> Interaction:
	var ir := Interaction.create(iid, a, b.id if b != null else -1, true)
	if ir == null:
		return null
	if not ir.start():
		return ir
	var guard := 0
	while ir.state != "finished" and ir.state != "cancelled" and guard < minutes_cap:
		ir.tick(1.0)
		guard += 1
	return ir

## Make the tests of `iid` pass for (a, b), then run it.
static func run_ok(a: Folk, b: Folk, iid: String) -> Interaction:
	var d: Dictionary = SimEnv.data().interaction_def(iid)
	CK.satisfy(a, null, d.get("tests", []), b)
	if b != null:
		CK.satisfy(b, null, d.get("target_tests", []), a)
	return run(a, b, iid)

static func tier_of(a: Folk) -> String:
	for i in range(SocialDynamics.outcome_log.size() - 1, -1, -1):
		if int(SocialDynamics.outcome_log[i]["actor"]) == a.id:
			return str(SocialDynamics.outcome_log[i]["tier"])
	return ""

static func expect(fails: Array, cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

static func pair_friendship(a: Folk, b: Folk) -> float:
	return a.get_rel(b.id, "friendship") + b.get_rel(a.id, "friendship")

## Set the clock (day, hour) via the shared kit.
static func set_time(day: int, hour: int, minute: int = 0) -> void:
	K.set_time(day, hour, minute)

## Run clock + director for n minutes (the director is created once per call).
static func director():
	if _dir == null or not is_instance_valid(_dir):
		_dir = K.director()
	return _dir

static func run_minutes(n: int) -> void:
	K.run(director(), n)

static func furnish_for_test(w: StubWorld) -> Dictionary:
	return K.Kit.furnish(w)
