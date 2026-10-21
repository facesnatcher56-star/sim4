class_name ParkingMarks
extends RefCounted
## Paint of the parking places (task 42), as flat quads for the floor mesh of LotChunks, from the places of VehicleBays: white bay lines on a forecourt (left, right and back line), end lines
## of a lay-by, and the dropped kerb of a driveway or bay: the footway tiles in front of a place are drawn in the paving of the driveway (the footway floor itself stays a footway: people walk
## over it and the walking graph is unchanged). Pure function of the places; cached until the map is made again (LotParking.add calls forget).
##   ParkingMarks.quads(chunk_rect) -> [[x0, z0, x1, z1, Color]]      ParkingMarks.kerb_tiles(chunk_rect) -> [Vector2i]      ParkingMarks.forget()

const LINE := 0.07
const WHITE := Color(0.74, 0.74, 0.70)

static var _quads: Array = []
static var _kerbs: Array = []
static var _ready: bool = false


static func forget() -> void:
	_quads.clear()
	_kerbs.clear()
	_ready = false


static func _build() -> void:
	_ready = true
	var w = WorldIface.world()
	if w == null or w.get("regions") == null or not w.regions.has_regions():
		return
	for r in w.regions.regions.values():
		if not w.regions.is_lot(int(r["id"])):
			continue
		for pl in VehicleBays.of(str(r["lot"])):
			var rc: Rect2 = pl["rect"]
			var x1: float = rc.end.x
			var y1: float = rc.end.y
			match str(pl["kind"]):
				"bay":
					_quads.append([rc.position.x, rc.position.y, rc.position.x + LINE, y1, WHITE])
					_quads.append([x1 - LINE, rc.position.y, x1, y1, WHITE])
					_quads.append([rc.position.x, rc.position.y, x1, rc.position.y + LINE, WHITE])
				"layby":
					_quads.append([rc.position.x, rc.position.y, rc.position.x + LINE, y1, WHITE])
					_quads.append([x1 - LINE, rc.position.y, x1, y1, WHITE])
					_quads.append([rc.position.x, rc.position.y, x1, rc.position.y + LINE, WHITE])
			var kr: Rect2 = pl["kerb"]
			for tx in range(int(floorf(kr.position.x)), int(ceilf(kr.end.x))):
				var t := Vector2i(tx, int(kr.position.y))
				if not _kerbs.has(t):
					_kerbs.append(t)


static func quads(rc: Rect2i) -> Array:
	if not _ready:
		_build()
	var out: Array = []
	var area := Rect2(Vector2(rc.position), Vector2(rc.size))
	for q in _quads:
		if area.intersects(Rect2(float(q[0]), float(q[1]), float(q[2]) - float(q[0]), float(q[3]) - float(q[1]))):
			out.append(q)
	return out


static func kerb_tiles(rc: Rect2i) -> Array:
	if not _ready:
		_build()
	var out: Array = []
	for t in _kerbs:
		if rc.has_point(t):
			out.append(t)
	return out
