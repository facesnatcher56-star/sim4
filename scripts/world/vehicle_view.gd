class_name VehicleView
extends Node3D
## The vehicle layer (task 12b), added to the LotView by VehicleView.ensure_on(lot_view). VIEW ONLY: it reads the sim (Transport.active / cars, the bus timetable,
## VehicleFeed, folk positions, light outages) and draws cars, buses, taxis, emergency vehicles, tow trucks and bikes on the road graph; it never writes sim
## state and never draws from a sim rng (its dice are a local RandomNumberGenerator). Vehicles exist only near a focus (the camera, the players' folk): far trips
## are just timings in the sim. At game speed 3 and above the layer is hidden (the folk it carries are shown again).
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
var lot_view: Node3D = null
var draw: bool = true                       # false: no meshes (tests)
var forced_focus: Array = []                # Vector2 (world x, z) points that replace the camera and the anchors (tests)
var active: bool = true
var rng: RandomNumberGenerator = RandomNumberGenerator.new()      # the view's own dice, never the sim's
var folk_nodes: Array = []                  # FolkView nodes near a focus, for the per-frame folk list
var _t: float = 0.0
var _focus_cache: Array = []


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
	sim.dark_fn = Callable(self, "_dark")


func _ready() -> void:
	var w = WorldIface.world()
	if w != null and w.has_signal("world_reset"):
		w.world_reset.connect(reset)


func reset() -> void:
	VehicleBays.forget()
	sim.vehicles.clear()
	ambient.reset()
	trips.reset()
	buses.reset()
	calls.reset()
	nodes.clear()
	signals.clear()


func _process(delta: float) -> void:
	advance(delta, Clock.speed)


## One frame. `speed` is the game speed (0 paused .. 3).
func advance(delta: float, speed: int) -> void:
	var was_active: bool = active
	active = speed <= int(cfg.get("max_speed", 2))
	if not active:
		if was_active:
			trips.release_all()
			sim.vehicles.clear()
			ambient.reset()
			buses.reset()
			calls.reset()
			nodes.clear()
		visible = false
		return
	visible = true
	var scale: float = float((cfg.get("speed_scale", [0.0, 1.0, 1.5]) as Array)[clampi(speed, 0, 2)])
	_t += delta
	if _t >= SYNC_EVERY or not was_active:
		_t = 0.0
		sync()
	var dt: float = delta * scale
	var steps: int = maxi(1, int(ceil(dt / 0.08)))
	_refresh_folks()
	for _i in steps:
		sim.step(dt / float(steps))
	trips.tick(dt)
	calls.tick(dt)
	buses.tick(dt)
	if draw:
		nodes.sync(self, sim.vehicles, sim.vt, float(cfg.get("hazard_flash_s", 0.45)))
		signals.update()


## The slow bookkeeping: what is near, who needs a vehicle.
func sync() -> void:
	_focus_cache = _compute_focus()
	ambient.sync()
	trips.sync()
	buses.sync()
	calls.sync()
	if draw:
		signals.sync()
	_cap()


func _cap() -> void:
	var maxn: int = int(cfg.get("max_vehicles", 46))
	if sim.vehicles.size() <= maxn:
		return
	for v in sim.vehicles.duplicate():
		if sim.vehicles.size() <= maxn:
			break
		if str(v["tag"]) == "ambient" and str(v["state"]) == "parked" and not in_range(v["pos"], 0.4):
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


func beyond_drop(p: Vector2) -> bool:
	var r: float = float(cfg.get("drop_radius", 80))
	for f in focus_points():
		if absf(p.x - (f as Vector2).x) <= r and absf(p.y - (f as Vector2).y) <= r:
			return false
	return true


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


## A folk that appears on top of an ambient car (a visitor arriving at a gate tile where the car stands): the car is simply not there any more.
func _clear_stood_on() -> void:
	for v in sim.vehicles:
		if str(v["tag"]) != "ambient" and str(v["tag"]) != "other":
			continue
		var h: Vector2 = v["dir"]
		var rt: Vector2 = VehicleRoads.right_of(h)
		for p in sim.folks:
			var d: Vector2 = p - (v["pos"] as Vector2)
			if d.length_squared() < 16.0 and absf(d.dot(h)) < float(v["len"]) * 0.5 - 0.2 and absf(d.dot(rt)) < float(v["wid"]) * 0.5 - 0.1:
				if str(v["tag"]) == "ambient":
					ambient.remove(v)
				else:
					sim.kill(v)
				break


## Game minutes (with the fraction of the current minute).
func now_f() -> float:
	return float(Clock.total_minutes) + Clock.frac()


## Vehicle seconds per game minute at the current speed (for pacing a vehicle to a timetable).
func vt_per_min(speed: int = -1) -> float:
	var sp: int = Clock.speed if speed < 0 else speed
	var rate: float = float(Clock.MIN_PER_SEC[clampi(sp, 0, 3)])
	var scale: float = float((cfg.get("speed_scale", [0.0, 1.0, 1.5]) as Array)[clampi(sp, 0, 2)])
	return scale / rate if rate > 0.0 else 1.0


func stats() -> Dictionary:
	var by: Dictionary = {}
	for v in sim.vehicles:
		by[str(v["kind"])] = int(by.get(str(v["kind"]), 0)) + 1
	return {"vehicles": sim.vehicles.size(), "by_kind": by, "nodes": nodes.count(), "ghosted": sim.ghosted}
