extends RefCounted
const K = preload("res://tests/vehicle_kit.gd")
func _plen(pts: Array) -> float:
	var l := 0.0
	for k in range(1, pts.size()):
		l += (pts[k] as Vector2).distance_to(pts[k - 1])
	return l
func run() -> Array:
	K.game("classic")
	var lots: Array = ["market", "hospital", "school", "office", "apartments", "works"]
	var bx := 8.5
	var d := {}
	var entry := {}
	var exit := {}
	for a in lots:
		var fa = VehicleRoads.frontage(a)
		var be := 1.0e9
		for e in VehicleRoads.edge_ends():
			var r = VehicleRoads.entry_route(e, fa, float(fa["gate"]) + bx, 1.0)
			if not r.is_empty():
				be = minf(be, _plen(r["pts"]))
		entry[a] = be
		var bx2 := 1.0e9
		for e in VehicleRoads.edge_ends():
			var r2 = VehicleRoads.exit_route(fa, float(fa["gate"]) + bx, e, 1.0)
			if not r2.is_empty():
				bx2 = minf(bx2, _plen(r2["pts"]))
		exit[a] = bx2
		for b in lots:
			if a == b: continue
			var fb = VehicleRoads.frontage(b)
			var leg = VehicleRoads.lane_route(fa, float(fa["gate"]) + bx, fb, float(fb["gate"]) + bx, 1.0)
			d[a + ">" + b] = _plen(leg["pts"])
	print("entry ", entry)
	print("exit ", exit)
	var perms: Array = []
	_perm(lots, [], perms)
	var best := 1.0e9
	var bo: Array = []
	for pm in perms:
		var tot: float = float(entry[pm[0]]) + float(exit[pm[5]])
		var inner := 0.0
		for i in range(5):
			inner += float(d[pm[i] + ">" + pm[i + 1]])
		if inner + tot < best:
			best = inner + tot
			bo = pm
	print("best open run ", bo, " total ", best)
	var inner2 := 0.0
	for i in range(5):
		inner2 += float(d[bo[i] + ">" + bo[i + 1]])
	print(" inner ", inner2, " entry ", entry[bo[0]], " exit ", exit[bo[5]])
	return []

func _perm(rest: Array, cur: Array, out: Array) -> void:
	if rest.is_empty():
		out.append(cur.duplicate())
		return
	for i in rest.size():
		var r = rest.duplicate()
		var x = r.pop_at(i)
		cur.append(x)
		_perm(r, cur, out)
		cur.pop_back()
