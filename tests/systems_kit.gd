extends RefCounted
## Shared helpers for systems_* tests (no run() method, so the runner skips it).

const Kit = preload("res://tests/sim_testkit.gd")

static var mgr: SystemsManager = null
static var notes: Array = []       # captured notifications [text, kind]
static var events: Array = []      # captured game events [name, payload]
static var _dirs: Array = []       # directors created by director(), freed in teardown()

## Fresh stub world + standalone Events/Data/Clock + reset systems + a SystemsManager listening.
static func setup(seed_value: int = 4242, with_manager: bool = true) -> StubWorld:
	var w: StubWorld = Kit.setup(seed_value)
	SysUtil.seed_rng(seed_value)
	SystemsManager.reset_all()
	PregnancyLoss.mature_on = 0            # tests that are not about loss or the early-pregnancy choice stay free of random events
	notes.clear()
	events.clear()
	SimEnv.events().notification.connect(func(t, k): notes.append([t, k]))
	SimEnv.events().game_event.connect(func(n, p): events.append([n, p]))
	SysContent.install()
	mgr = null
	if with_manager:
		mgr = SystemsManager.new()
		mgr.autosave_enabled = false
		mgr.setup()
	return w

static func director():
	var d = Kit.director()
	_dirs.append(d)
	return d

static func teardown() -> void:
	for d in _dirs:
		if is_instance_valid(d):
			d.free()
	_dirs.clear()
	if mgr != null:
		mgr.teardown()
		mgr.free()
		mgr = null
	SystemsManager.reset_all()
	Kit.teardown()

static func count_events(ev_name: String) -> int:
	var n: int = 0
	for e in events:
		if e[0] == ev_name:
			n += 1
	return n

static func last_event(ev_name: String) -> Dictionary:
	for i in range(events.size() - 1, -1, -1):
		if events[i][0] == ev_name:
			return events[i][1]
	return {}

static func has_note(fragment: String) -> bool:
	for n in notes:
		if str(n[0]).find(fragment) >= 0:
			return true
	return false

static func make_folk(w: StubWorld, fname: String, traits: Array = [], hid: int = 1, tile: Vector2i = Vector2i(12, 12), stage: String = "adult") -> Folk:
	var f := Folk.create(fname, traits)
	f.household_id = hid
	f.age_stage = stage
	w.add_folk(f, tile)
	Aging.register(f)
	Goals.ensure_profile(f)
	return f

static func expect(fails: Array, cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

## Deep equality that treats ints and floats as numbers.
static func deep_eq(a: Variant, b: Variant, path: String = "", out: Array = []) -> bool:
	var ta: int = typeof(a)
	var tb: int = typeof(b)
	if (ta == TYPE_INT or ta == TYPE_FLOAT) and (tb == TYPE_INT or tb == TYPE_FLOAT):
		if absf(float(a) - float(b)) > 0.0001:
			out.append("%s: %s != %s" % [path, str(a), str(b)])
			return false
		return true
	if ta != tb:
		out.append("%s: type %d != %d (%s vs %s)" % [path, ta, tb, str(a), str(b)])
		return false
	if ta == TYPE_DICTIONARY:
		var da: Dictionary = a
		var db: Dictionary = b
		var ok: bool = true
		for k in da:
			if not db.has(k):
				out.append("%s.%s missing in B" % [path, str(k)])
				ok = false
			elif not deep_eq(da[k], db[k], path + "." + str(k), out):
				ok = false
		for k2 in db:
			if not da.has(k2):
				out.append("%s.%s missing in A" % [path, str(k2)])
				ok = false
		return ok
	if ta == TYPE_ARRAY:
		var aa: Array = a
		var ab: Array = b
		if aa.size() != ab.size():
			out.append("%s: size %d != %d" % [path, aa.size(), ab.size()])
			return false
		var ok2: bool = true
		for i in aa.size():
			if not deep_eq(aa[i], ab[i], "%s[%d]" % [path, i], out):
				ok2 = false
		return ok2
	if a != b:
		out.append("%s: %s != %s" % [path, str(a), str(b)])
		return false
	return true

## Advance the clock and tick the director n minutes.
static func run(dir, n: int) -> void:
	Kit.run_minutes(dir, n)

static func set_time(day: int, hour: int, minute: int = 0) -> void:
	Kit.set_time(day, hour, minute)
