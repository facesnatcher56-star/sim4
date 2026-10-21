class_name VehicleView
extends Node3D
## The vehicle layer (task 12b), added to the LotView by VehicleView.ensure_on(lot_view). VIEW ONLY: it reads the sim (Transport.active / cars, the bus timetable,
## VehicleFeed, folk positions, light outages) and draws cars, buses, taxis, emergency vehicles, tow trucks and bikes on the road graph; it never writes sim
## state and never draws from a sim rng (its dice are a local RandomNumberGenerator). Vehicles exist only near a focus (the camera, the players' folk): far trips
## are just timings in the sim. At every game speed the vehicles stay drawn and move at the faster rate (data speed_scale). NOTHING appears or disappears on the picture:
## spawn and removal only happen off screen (VehicleView.on_screen is the frustum of the camera plus a margin), at the map edge, into a bay or a garage.
## Parts: VehicleSim (movement), VehicleNodes (bodies), VehicleAmbient (parked and passing cars), VehicleTrips (riders of the players' trips),
## VehicleBuses (the timetable bus bodies), VehicleCalls (emergency units, crashes and the tow), VehicleSignals (traffic light heads).
##   view.advance(dt_real, speed)   one frame of work (also used by tests without a window)      view.sync()   the 0.4 s bookkeeping
##   view.in_range(p) / view.focus_points()      view.sim.vehicles      view.stats()

const SYNC_EVERY := 0.4

var cfg: Dictionary = {}
var sim: VehicleSim = null
var nodes: VehicleNodes = null
var ambient: VehicleAmbient = null
var trips: VehicleTrips = null
var buses: VehicleBuses = null
var calls: VehicleCalls = null
var signals: VehicleSignals = null
var filler: VehicleFiller = null
var walkers: VehicleWalkers = null
var props: ParkingProps = null                 # carports (display only, made when the layer draws)
var lot_view: Node3D = null
var draw: bool = true                       # false: no meshes (tests)
var forced_focus: Array = []                # Vector2 (world x, z) points that replace the camera and the anchors (tests)
var active: bool = true
var rng: RandomNumberGenerator = RandomNumberGenerator.new()      # the view's own dice, never the sim's
var folk_nodes: Array = []                  # FolkView nodes near a focus, for the per-frame folk list
var seeding: bool = true                    # the first bookkeeping after a (re)start: the road is filled in, so vehicles may appear in view this once
var screen_fn: Callable = Callable()        # tests: (Vector2 world point, margin) -> bool "is on the picture"
var _t: float = 0.0
var _focus_cache: Array = []
var _seed_syncs: int = 0


static func ensure_on(lv: Node3D) -> VehicleView:
	var existing = lv.get_node_or_null("VehicleView")
	if existing != null:
		return existing
	var vv := VehicleView.new()
	vv.name = "VehicleView"
	vv.lot_view = lv
	lv.add_child(vv)
	return vv


func _init() -> void:
	cfg = SysUtil.table("vehicles")
	rng.seed = 424242
	sim = VehicleSim.new(cfg)
	nodes = VehicleNodes.new()
	ambient = VehicleAmbient.new(self)
	trips = VehicleTrips.new(self)
	buses = VehicleBuses.new(self)
	calls = VehicleCalls.new(self)
	signals = VehicleSignals.new(self)
	filler = VehicleFiller.new(self)
	walkers = VehicleWalkers.new(self)
	sim.dark_fn = Callable(self, "_dark")
	sim.retire_fn = Callable(self, "retire_ok")


func _ready() -> void:
	if draw:
		props = ParkingProps.new()
		props.name = "ParkingProps"
		add_child(props)
	var w = WorldIface.world()
	if w != null and w.has_signal("world_reset"):
		w.world_reset.connect(reset)
	var ev = get_node_or_null("/root/Events")
	if ev != null:
		ev.game_event.connect(_on_game_event)


## Task 53: a parked car the pawn drove off with is now theirs: the same body, tagged as an owner car (it leaves only with them).
func _on_game_event(ev_name: String, p: Dictionary) -> void:
	if ev_name != "car_taken":
		return
	for v in sim.vehicles:
		if str(v.get("key", "")) == str(p.get("key", "")):
			v["tag"] = "owner"
			v["key"] = "car:%d" % int(p.get("car", -1))


func reset() -> void:
	VehicleBays.forget()
	ParkingMarks.forget()
	if props != null:
		props.dirty = true
	sim.vehicles.clear()
	ambient.reset()
	trips.reset()
	buses.reset()
	calls.reset()
	nodes.clear()
	signals.clear()
	filler.reset()
	walkers.clear()
	seeding = true
	_seed_syncs = 0


func _process(delta: float) -> void:
	advance(delta, Clock.speed)


## One frame. `speed` is the game speed (0 paused .. 3).
func advance(delta: float, speed: int) -> void:
	var was_active: bool = active
	active = speed <= int(cfg.get("max_speed", 3))
	if not active:
		if was_active:
			walkers.clear()
			trips.release_all()
			sim.vehicles.clear()
			ambient.reset()
			buses.reset()
			calls.reset()
			nodes.clear()
		visible = false
		return
	visible = true
	var scale: float = speed_scale(speed)
	_t += delta
	if _t >= SYNC_EVERY or not was_active:
		_t = 0.0
		sync()
	var dt: float = delta * scale
	var steps: int = clampi(int(ceil(dt / 0.08)), 1, 8)           # fewer, larger steps when the frame is long; the sim copes with 0.08 s and a little more
	_refresh_folks()
	sim.hour = SysUtil.hour_f()
	for _i in steps:
		sim.step(dt / float(steps))
	walkers.tick(dt)
	trips.tick(dt)
	calls.tick(dt)
	buses.tick(dt)
	if draw:
		nodes.cam_ground = camera_ground()
		nodes.sync(self, sim.vehicles, sim.vt, float(cfg.get("hazard_flash_s", 0.45)))
		signals.update()


## The slow bookkeeping: what is near, who needs a vehicle.
func sync() -> void:
	_focus_cache = _compute_focus()
	ambient.sync()
	filler.sync()
	trips.sync()
	buses.sync()
	calls.sync()
	if draw:
		signals.sync()
		props.sync()
	_cap()


func _cap() -> void:
	_seed_syncs += 1
	if _seed_syncs > 2:
		seeding = false
	var maxn: int = int(cfg.get("max_vehicles", 60))
	if sim.vehicles.size() <= maxn:
		return
	for v in sim.vehicles.duplicate():
		if sim.vehicles.size() <= maxn:
			break
		if str(v["tag"]) == "ambient" and str(v["state"]) == "parked" and not on_screen(v["pos"], 10.0):
			ambient.remove(v)


# ------------------------------------------------------------------ where things are
func _compute_focus() -> Array:
	if not forced_focus.is_empty():
		return forced_focus
	var out: Array = []
	if Tiers.has_focus("cam"):
		var t: Vector2i = Tiers.focus_of("cam")
		out.append(Vector2(float(t.x) + 0.5, float(t.y) + 0.5))
	for f in SysUtil.residents():
		out.append(Vector2(float(f.tile.x) + 0.5, float(f.tile.y) + 0.5))
		if out.size() >= 6:
			break
	return out


## Where the camera looks on the ground (the real lights of the vehicles go to those nearest to it).
func camera_ground() -> Vector2:
	var t: Variant = lot_view.get("_target") if lot_view != null else null
	if t is Vector3:
		return Vector2((t as Vector3).x, (t as Vector3).z)
	var f: Array = focus_points()
	return f[0] if not f.is_empty() else Vector2.ZERO


func focus_points() -> Array:
	if _focus_cache.is_empty():
		_focus_cache = _compute_focus()
	return _focus_cache


## Is the world point near a focus? `k` scales the radius (1 = view radius, 0.4 = the part you could see without panning).
func in_range(p: Vector2, k: float = 1.0) -> bool:
	var r: float = float(cfg.get("view_radius", 62)) * k
	for f in focus_points():
		if absf(p.x - (f as Vector2).x) <= r and absf(p.y - (f as Vector2).y) <= r:
			return true
	return false


## Is the world point on the picture (the camera's frustum), grown by `margin` tiles? Without a camera (tests, headless) the part of the map around the
## focus that you could see without panning counts as the picture.
func on_screen(p: Vector2, margin: float = 6.0) -> bool:
	if screen_fn.is_valid():
		return bool(screen_fn.call(p, margin))
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() and get_viewport() != null else null
	if cam == null:
		return in_range(p, 0.45)
	for o in [Vector2.ZERO, Vector2(margin, 0), Vector2(-margin, 0), Vector2(0, margin), Vector2(0, -margin)]:
		if cam.is_position_in_frustum(Vector3(p.x + o.x, 0.5, p.y + o.y)):
			return true
	return false


## May a vehicle at `p` be taken out of the world? Only outside the drop radius of every focus AND off the picture (task 37: nothing vanishes in view).
func beyond_drop(p: Vector2) -> bool:
	var r: float = float(cfg.get("drop_radius", 80))
	for f in focus_points():
		if absf(p.x - (f as Vector2).x) <= r and absf(p.y - (f as Vector2).y) <= r:
			return false
	return not on_screen(p, 10.0)


## May a vehicle at the end of its path go (it is off the picture)?
func retire_ok(p: Vector2) -> bool:
	return not on_screen(p, 4.0)


func speed_scale(speed: int) -> float:
	var a: Array = cfg.get("speed_scale", [0.0, 1.0, 1.5, 3.0])
	return float(a[clampi(speed, 0, a.size() - 1)])


func _dark(i: int, j: int) -> bool:
	return TransportTraffic.lights_out(TransportTraffic.zone_of_tile(VehicleRoads.junction_tile(i, j)))      # the power zone of the sim (TransportTraffic) decides, not the lattice


## Positions of folk on the street (and anywhere near a focus) that vehicles must not run over: riders hidden in a vehicle do not count.
func _refresh_folks() -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	if lot_view != null and lot_view.has_method("get_folk_view"):
		for f in World.all_folk():
			var fv = lot_view.get_folk_view(f.id)
			if fv != null and fv.visible and not fv.has_meta("in_vehicle"):
				var p := Vector2(fv.position.x, fv.position.z)
				if in_range(p):
					pts.append(p)
	else:
		for f in World.all_folk():
			if not trips.is_riding(int(f.id)):
				var p2 := Vector2(float(f.tile.x) + 0.5, float(f.tile.y) + 0.5)
				if in_range(p2):
					pts.append(p2)
	sim.folks = pts
	_clear_stood_on()


## A folk that appears on top of a parked ambient car (a visitor arriving at a gate tile where the car stands): the car does not vanish, its driver has come back to it and it
## drives off (it is not hidden or removed in view).
func _clear_stood_on() -> void:
	for v in sim.vehicles:
		if str(v["tag"]) != "ambient" or str(v["state"]) != "parked" or v.has("leaving") or v.has("dest_lot"):
			continue
		var h: Vector2 = v["dir"]
		var rt: Vector2 = VehicleRoads.right_of(h)
		for p in sim.folks:
			var d: Vector2 = p - (v["pos"] as Vector2)
			if d.length_squared() < 16.0 and absf(d.dot(h)) < float(v["len"]) * 0.5 - 0.2 and absf(d.dot(rt)) < float(v["wid"]) * 0.5 - 0.1:
				ambient._leave(v)
				break


## Game minutes (with the fraction of the current minute).
func now_f() -> float:
	return float(Clock.total_minutes) + Clock.frac()


## Vehicle seconds per game minute at the current speed (for pacing a vehicle to a timetable).
func vt_per_min(speed: int = -1) -> float:
	var sp: int = Clock.speed if speed < 0 else speed
	var rate: float = float(Clock.MIN_PER_SEC[clampi(sp, 0, 3)])
	var scale: float = speed_scale(sp)
	return scale / rate if rate > 0.0 else 1.0


func stats() -> Dictionary:
	var by: Dictionary = {}
	for v in sim.vehicles:
		by[str(v["kind"])] = int(by.get(str(v["kind"]), 0)) + 1
	return {"vehicles": sim.vehicles.size(), "by_kind": by, "nodes": nodes.count(), "ghosted": sim.ghosted}
