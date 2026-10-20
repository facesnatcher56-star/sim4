class_name VehicleProbes
extends RefCounted
## What is in a vehicle's way (task 37, split out of VehicleSim): other vehicles and people ahead along its own path. Plain functions over a VehicleSim.
##   obstacle_limit(sim, v, half) -> the speed limit the things ahead put on v (INF when the way is free); sets v.wait_for (who it waits for) and v.wait_folk
## Cause: a vehicle brakes for anything whose body comes within its own width of the way ahead (centre line and nose) over the distance it needs to stop; of two vehicles
## that meet (crossing or oncoming) the older goes first and the younger gives way, a stationary one is always given way to.
## Speed: neighbours come from the 16 m grid of the step, a vehicle's body points are made once per step, the points of v's own way come from a per-path table.

## Body sample points of a vehicle (cached for the step: every vehicle that looks at it uses the same ones).
static func body_pts(sim: VehicleSim, o: Dictionary) -> PackedVector2Array:
	var id: int = int(o["id"])
	if sim._body_cache.has(id):
		return sim._body_cache[id]
	var ohd: Vector2 = o["dir"]
	var ort: Vector2 = VehicleRoads.right_of(ohd)
	var ow: float = float(o["wid"]) * 0.5 * 0.95
	var ol: float = float(o["len"]) * 0.5 * 0.95
	var nl: int = int(ceil(ol * 2.0 / 1.1))
	var pts_o := PackedVector2Array()
	var opos: Vector2 = o["pos"]
	for ia in nl + 1:
		var sx: float = -1.0 + 2.0 * float(ia) / float(nl)
		pts_o.append(opos + ohd * (ol * sx) + ort * ow)
		pts_o.append(opos + ohd * (ol * sx))
		pts_o.append(opos + ohd * (ol * sx) - ort * ow)
	sim._body_cache[id] = pts_o
	return pts_o


static func obstacle_limit(sim: VehicleSim, v: Dictionary, half: float) -> float:
	var h: Vector2 = v["dir"]
	var lim: float = INF
	sim._blocker = {}
	var look: float = sim.num("look", 6.0) + float(v["v"]) * 0.6
	var gap: float = sim.num("gap", 0.9)
	var pos: Vector2 = v["pos"]
	var wid: float = float(v["wid"])
	var vpath: VehiclePath = v["path"]
	var full_h: float = look + half + 6.0
	var sdd := PackedFloat32Array()                         # the points of my own way ahead (centre and nose), made once and only when somebody is near
	var spc := PackedVector2Array()
	var snose := PackedVector2Array()
	var made: bool = false
	var span: float = full_h + 6.5                          # nothing farther than this can be in my way (the longest body is 8.4)
	var c0 := Vector2i(int(floorf((pos.x - span) / VehicleSim.CELL)), int(floorf((pos.y - span) / VehicleSim.CELL)))
	var c1 := Vector2i(int(floorf((pos.x + span) / VehicleSim.CELL)), int(floorf((pos.y + span) / VehicleSim.CELL)))
	var near: Array = []
	for cx in range(c0.x, c1.x + 1):
		for cy in range(c0.y, c1.y + 1):
			var cell = sim._grid.get(Vector2i(cx, cy))
			if cell != null:
				near.append_array(cell)
	for o in near:
		if o == v or str(o["state"]) == "dead":
			continue
		var d: Vector2 = (o["pos"] as Vector2) - pos
		var oh: float = float(o["len"]) * 0.5
		var reach: float = full_h + oh + 2.0
		if d.length_squared() > reach * reach or d.dot(h) < -(oh + half + 0.3):
			continue                                             # out of my way: too far, or behind me
		var cs: float = h.dot(o["dir"])
		var margin: float = wid * 0.5 + 0.12
		var near_only: bool = false
		if cs < -0.7:
			margin = wid * 0.5                                   # oncoming in the other lane: only a real intrusion counts (a left turn across it gives way by age)
		if cs <= 0.7:
			var yields: bool = int(o["id"]) < int(v["id"]) or float(o["v"]) < 0.3
			if not yields:
				continue                                         # the other one gives way to me
		if int(o.get("wait_for", -1)) == int(v["id"]):
			near_only = true                                     # it waits for me (a deadlock in the making): only stop for it when it is really in my way
		if not made:
			made = true
			var tc: PackedVector2Array = vpath.table("c", float(v["len"]))
			var tn: PackedVector2Array = vpath.table("n", half * 0.9)
			var dd0: float = 0.2
			while dd0 <= full_h:
				var sp0: float = float(v["s"]) + dd0
				if sp0 > vpath.length + 0.5:
					break
				var ti: int = clampi(int(roundf(sp0 / VehiclePath.TABLE_STEP)), 0, tc.size() - 1)
				sdd.append(dd0)
				spc.append(tc[ti])
				snose.append(tn[ti])
				dd0 += 0.8
		var best: float = INF
		var pts_o: PackedVector2Array = body_pts(sim, o)
		var opos: Vector2 = o["pos"]
		var rad: float = oh + float(o["wid"]) * 0.5 + margin + 0.2     # every body point is within this of the body centre
		var rad2: float = rad * rad
		var horizon: float = 2.4 if near_only else full_h
		var m2: float = margin * margin
		for k in sdd.size():
			if sdd[k] > horizon:
				break
			var pc: Vector2 = spc[k]
			var nose: Vector2 = snose[k]
			if opos.distance_squared_to(pc) > rad2 and opos.distance_squared_to(nose) > rad2:
				continue
			for q in pts_o:
				if q.distance_squared_to(nose) < m2 or q.distance_squared_to(pc) < m2:
					best = sdd[k]
					break
			if best < INF:
				break
		if best < INF:
			var bl: float = sim._brake(best - gap)
			if bl < lim:
				lim = bl
				sim._blocker = o
				v["wait_for"] = int(o["id"])
	var folk_near: bool = false
	if not sim.folks.is_empty():
		var fr2: float = look + half * 2.0 + 3.0
		for fp in sim.folks:
			if fp.distance_squared_to(pos) < fr2 * fr2:
				folk_near = true
				break
	if folk_near:
		var vpath2: VehiclePath = v["path"]
		var fm: float = wid * 0.5 + 0.35
		var d2: float = 0.2
		var hz: float = look + half
		while d2 <= hz:
			var sp2: float = float(v["s"]) + d2
			if sp2 > vpath2.length + 0.5:
				break
			var c2: Vector2 = VehicleSim.centre(vpath2, sp2, float(v["len"]))
			var n2: Vector2 = vpath2.at(minf(sp2 + half * 0.9, vpath2.length))
			var hit_f: Vector2 = Vector2.INF
			var r2: Vector2 = vpath2.at(maxf(sp2 - half * 0.9, 0.0))
			var m1: Vector2 = vpath2.at(minf(sp2 + half * 0.45, vpath2.length))
			var m2: Vector2 = vpath2.at(maxf(sp2 - half * 0.45, 0.0))
			for p in sim.folks:
				if p.distance_squared_to(n2) < fm * fm or p.distance_squared_to(c2) < fm * fm or p.distance_squared_to(r2) < fm * fm or p.distance_squared_to(m1) < fm * fm or p.distance_squared_to(m2) < fm * fm:
					hit_f = p
					break
			if hit_f != Vector2.INF:
				var fl: float = sim._brake(d2 - 0.4)
				if fl < lim:
					lim = fl
					v["wait_folk"] = true
					sim._blocker = {"kind": "folk", "state": "stand", "pos": hit_f, "tag": "folk"}
				break
			d2 += 0.7
	return lim
