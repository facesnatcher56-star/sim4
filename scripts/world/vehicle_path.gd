class_name VehiclePath
extends RefCounted
## A polyline on the ground (x, z in tiles) with cumulative lengths: where a vehicle is at distance `s`, which way it faces, where it passes a point.
## Corners are rounded so a vehicle turns instead of pivoting. View layer only (see data/vehicles.json).

var pts: PackedVector2Array = PackedVector2Array()
var cum: PackedFloat32Array = PackedFloat32Array()
var length: float = 0.0
var _tables: Dictionary = {}                 # "kind|size" -> PackedVector2Array of points along the way every TABLE_STEP (for the obstacle probes of VehicleSim)

const TABLE_STEP := 0.4


static func make(points: Array, radius: float = 1.8) -> VehiclePath:
	var clean: Array = []
	for p in points:
		var v: Vector2 = p
		if clean.is_empty() or (clean[clean.size() - 1] as Vector2).distance_to(v) > 0.01:
			clean.append(v)
	var vp := VehiclePath.new()
	var out: Array = []
	for i in clean.size():
		var v: Vector2 = clean[i]
		if i == 0 or i == clean.size() - 1 or radius <= 0.0:
			out.append(v)
			continue
		var a: Vector2 = clean[i - 1]
		var b: Vector2 = clean[i + 1]
		var din: Vector2 = (v - a)
		var dout: Vector2 = (b - v)
		var r: float = minf(radius, minf(din.length(), dout.length()) * 0.45)
		din = din.normalized()
		dout = dout.normalized()
		if absf(din.cross(dout)) < 0.02 or r < 0.2:
			out.append(v)
			continue
		var p0: Vector2 = v - din * r
		var p2: Vector2 = v + dout * r
		for k in 5:
			var t: float = float(k) / 4.0
			out.append(p0.lerp(v, t).lerp(v.lerp(p2, t), t))
	vp.pts = PackedVector2Array(out)
	vp.cum.resize(vp.pts.size())
	var acc: float = 0.0
	for i in vp.pts.size():
		if i > 0:
			acc += vp.pts[i].distance_to(vp.pts[i - 1])
		vp.cum[i] = acc
	vp.length = acc
	return vp


func _seg(s: float) -> int:
	var lo: int = 0
	var hi: int = pts.size() - 1
	while hi - lo > 1:
		var mid: int = (lo + hi) / 2
		if cum[mid] <= s:
			lo = mid
		else:
			hi = mid
	return lo


func at(s: float) -> Vector2:
	if pts.size() < 2:
		return pts[0] if pts.size() == 1 else Vector2.ZERO
	var c: float = clampf(s, 0.0, length)
	var i: int = _seg(c)
	var seg_len: float = maxf(cum[i + 1] - cum[i], 0.0001)
	return pts[i].lerp(pts[i + 1], (c - cum[i]) / seg_len)


func dir_at(s: float) -> Vector2:
	if pts.size() < 2:
		return Vector2(0, -1)
	var c: float = clampf(s, 0.0, length)
	var i: int = _seg(c)
	return (pts[i + 1] - pts[i]).normalized()


## Distance along the path of the point nearest to `p`, looking only at s in [from_s, from_s + window].
func closest_s(p: Vector2, from_s: float = 0.0, window: float = 1.0e9) -> float:
	var best: float = from_s
	var best_d: float = 1.0e18
	for i in range(pts.size() - 1):
		if cum[i + 1] < from_s or cum[i] > from_s + window:
			continue
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var ab: Vector2 = b - a
		var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d: float = (a + ab * t).distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = cum[i] + sqrt(ab.length_squared()) * t
	return best


## The point a vehicle of body length `blen` has as its centre when its reference distance is s = i x TABLE_STEP (kind "c", see VehicleSim.centre) or the point `ahead`
## in front of the reference (kind "n", the nose). Built once per path and size, then indexed: the probes ask for the same points every step.
func table(kind: String, size: float) -> PackedVector2Array:
	var key := "%s|%.2f" % [kind, size]
	if _tables.has(key):
		return _tables[key]
	var out := PackedVector2Array()
	var n: int = int(ceil(length / TABLE_STEP)) + 1
	out.resize(n)
	for i in n:
		var s: float = float(i) * TABLE_STEP
		if kind == "c":
			out[i] = at(s) if size < 3.0 else (at(minf(s + size * 0.4, length)) + at(maxf(s - size * 0.4, 0.0))) * 0.5
		else:
			out[i] = at(minf(s + size, length))
	_tables[key] = out
	return out
