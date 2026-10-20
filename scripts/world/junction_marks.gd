class_name JunctionMarks
extends RefCounted
## Paint on the road at the junctions of the street lattice (task 37), as flat quads for the floor mesh of LotChunks, from what VehicleControl says each junction is:
##   stop lines (solid) on every way into a traffic light and on the side street of a stop sign, dashed give-way lines on a give-way sign and at the mini roundabout,
##   the ring of dots around a roundabout island, a hatched yellow box at the big crossings, turn arrows on the ways the data lists, zebra bars only on the arms with a
##   crossing (the other arms are plain asphalt: people still walk over them, nothing is painted), and worn paint (junction `worn` 0..0.8 fades the white and drops bars).
## Pure function of the layout and data/junctions.json: no nodes, no randomness. Cached per layout.
##   JunctionMarks.quads(chunk_rect) -> [[x0, z0, x1, z1, Color], ...]      JunctionMarks.zebra_color(tile) -> Color or null (no bars)

const E := 0
const S := 1
const W := 2
const N := 3
const ARM_OF_DIR := {0: "W", 1: "N", 2: "E", 3: "S"}     # a vehicle heading E comes in by the west arm, and so on

static var _all: Array = []
static var _ready: bool = false


static func forget() -> void:
	_all.clear()
	_ready = false


static func _road_color() -> Color:
	return Color(0.29, 0.30, 0.33)


static func _fade(col: Color, worn: float) -> Color:
	return col.lerp(_road_color(), clampf(worn, 0.0, 0.8) * 0.75)


## Axis-aligned rectangle from a heading `f` (unit, axis-aligned), the lane centre point `a`, distances along (a0..a1) and across (w0..w1, positive = right of f).
static func _rect(a: Vector2, f: Vector2, a0: float, a1: float, w0: float, w1: float) -> Array:
	var r := VehicleRoads.right_of(f)
	var p := a + f * a0 + r * w0
	var q := a + f * a1 + r * w1
	return [minf(p.x, q.x), minf(p.y, q.y), maxf(p.x, q.x), maxf(p.y, q.y)]


static func quads(rc: Rect2i) -> Array:
	if not _ready:
		_build()
	var out: Array = []
	for q in _all:
		if q[2] >= float(rc.position.x) and q[0] <= float(rc.end.x) and q[3] >= float(rc.position.y) and q[1] <= float(rc.end.y):
			out.append(q)
	return out


static func _add(r: Array, col: Color) -> void:
	_all.append([r[0], r[1], r[2], r[3], col])


static func _build() -> void:
	_ready = true
	_all.clear()
	var ctl: VehicleControl = VehicleControl.shared()
	var nx: int = VehicleRoads.xs().size()
	var ny: int = VehicleRoads.ys().size()
	for i in nx:
		for j in ny:
			_junction(ctl, ctl.info(i, j), i, j, nx, ny)


static func _arm_exists(i: int, j: int, dir: int, nx: int, ny: int) -> bool:
	# the arm a vehicle heading `dir` comes in by: heading E = west arm (needs i > 0), S = north arm (j > 0), W = east arm (i < nx - 1), N = south arm (j < ny - 1)
	match dir:
		E:
			return i > 0
		S:
			return j > 0
		W:
			return i < nx - 1
	return j < ny - 1


static func _junction(ctl: VehicleControl, d: Dictionary, i: int, j: int, nx: int, ny: int) -> void:
	var ctr: Vector2 = VehicleRoads.junction_center(i, j)
	var worn: float = float(d["worn"])
	var white := Color(0.80, 0.80, 0.76)
	var type: String = str(d["type"])
	var lane: float = 1.0
	for dir in 4:
		if not _arm_exists(i, j, dir, nx, ny):
			continue
		var f := Vector2(VehicleRoads.DIRS[dir])
		# the point on the lane centre where the vehicle's nose stops: 4.5 + 0.4 before the junction centre (VehicleSim stop line)
		var a: Vector2 = ctr - f * 4.9 + VehicleRoads.right_of(f) * lane
		var minor: bool = VehicleRoads.axis_of(dir) == int(d.get("minor", -1))
		match type:
			"signal":
				_add(_rect(a, f, -0.15, 0.15, -0.95, 0.95), _fade(white, worn))
			"stop":
				if minor:
					_add(_rect(a, f, -0.15, 0.15, -0.95, 0.95), _fade(white, worn))
			"giveway", "roundabout":
				if minor or type == "roundabout":
					var k: int = 0
					var w: float = -0.95
					while w < 0.9:
						if worn < 0.5 or (k % 3) != 1:
							_add(_rect(a, f, -0.12, 0.12, w, w + 0.34), _fade(white, worn))
						w += 0.56
						k += 1
		if (d.get("arrows", []) as Array).has(ARM_OF_DIR[dir]) and type == "signal":
			_arrow(a - f * 3.6, f, _fade(white, worn))
	if type == "roundabout":
		for k in 12:
			var ang: float = float(k) / 12.0 * TAU
			var p: Vector2 = ctr + Vector2(cos(ang), sin(ang)) * 2.25
			_add([p.x - 0.15, p.y - 0.15, p.x + 0.15, p.y + 0.15], _fade(white, worn))
	if bool(d.get("box", false)):
		var yellow := Color(0.82, 0.68, 0.16)
		var x0: float = ctr.x - 2.0
		var y0: float = ctr.y - 2.0
		for k in 5:
			var o: float = float(k)
			_add([x0 + o - 0.05, y0, x0 + o + 0.05, y0 + 4.0], _fade(yellow, worn * 0.6))
			_add([x0, y0 + o - 0.05, x0 + 4.0, y0 + o + 0.05], _fade(yellow, worn * 0.6))


## A left-turn-and-ahead arrow on the lane: stem, a stepped head ahead and a branch to the left with a small head (left of the heading is negative "across").
static func _arrow(a: Vector2, f: Vector2, col: Color) -> void:
	_add(_rect(a, f, 0.0, 2.0, -0.11, 0.11), col)
	for k in 3:
		var w: float = 0.55 - 0.2 * float(k)
		_add(_rect(a, f, 2.0 + 0.2 * float(k), 2.2 + 0.2 * float(k), -w, w), col)
	_add(_rect(a, f, 1.0, 1.22, -0.9, 0.0), col)
	for k2 in 3:
		var half: float = 0.45 - 0.15 * float(k2)
		_add(_rect(a, f, 1.11 - half, 1.11 + half, -0.9 - 0.14 * float(k2 + 1), -0.9 - 0.14 * float(k2)), col)


## Colour of the zebra bars of a crossing tile (faded by the junction's worn paint), or null when this arm has no painted crossing.
static func zebra_color(tile: Vector2i) -> Variant:
	var ctl: VehicleControl = VehicleControl.shared()
	var z: Dictionary = ctl.zebra_at(tile)
	if z.is_empty() or not ctl.zebra_arms(int(z["i"]), int(z["j"])).has(str(z["arm"])):
		return null
	var worn: float = float(ctl.info(int(z["i"]), int(z["j"]))["worn"])
	# worn paint also loses bars: a stripe is missing where the tile hash says so
	if worn > 0.45 and VehicleControl.mix01("bar|%d|%d" % [tile.x, tile.y]) < worn * 0.5:
		return null
	return _fade(Color(0.78, 0.78, 0.74), worn)
