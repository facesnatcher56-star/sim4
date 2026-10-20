class_name VehicleJams
extends RefCounted
## Jams of the vehicle layer (task 37; replaces the old "ghost" that faded a stuck vehicle through the one in its way). A vehicle that has been waiting for another vehicle for
## jam_after_s seconds (data/vehicles.json) calls resolve(): it follows who waits for whom.
##   * a CYCLE (A waits for B waits for A, e.g. two cars that block each other in a box or at a gate): the youngest car of the cycle backs up along its own path, a few metres, and
##     then waits for the others to pass. Cause: with nobody able to go forward the only way out is for one to give way backwards; the youngest gives way (older has priority).
##   * a chain that ends in a person standing on the road, a bus at its stop, a red light or a stop sign: not a deadlock, the vehicles just wait (the cause is logged).
## Nothing is ever hidden, faded or driven through. Every jam leaves a record in sim.jam_log: {cause, ids, kinds, tags, pos, t}.
##   resolve(sim, v)      hold(sim, v, dt) -> true while the vehicle is backing up or waiting after it       by_id(sim, id)

const REVERSE_M := 6.0
const REVERSE_SPEED := 2.2
const WAIT_AFTER_S := 4.0


static func by_id(sim: VehicleSim, id: int) -> Dictionary:
	for o in sim.vehicles:
		if int(o["id"]) == id:
			return o
	return {}


static func resolve(sim: VehicleSim, v: Dictionary) -> void:
	v["blocked_t"] = 0.0
	var chain: Array = [int(v["id"])]
	var cur: Dictionary = v
	var cause: String = "queue"
	var cycle: Array = []
	while chain.size() < 14:
		var w: int = int(cur.get("wait_for", -1))
		if w < 0:
			if str(cur["state"]) == "parked" or bool(cur.get("end_hold", false)):
				cause = "parked"
			elif str(cur["state"]) == "dwell":
				cause = "dwell"
			elif bool(cur.get("wait_folk", false)):
				cause = "folk"
			else:
				cause = "light_or_sign"
			break
		if chain.has(w):
			cycle = chain.slice(chain.find(w))
			cause = "cycle"
			break
		var nxt: Dictionary = by_id(sim, w)
		if nxt.is_empty():
			break
		chain.append(w)
		cur = nxt
	var kinds: Array = []
	var tags: Array = []
	for id in chain:
		var o: Dictionary = by_id(sim, int(id))
		kinds.append(str(o.get("kind", "?")))
		tags.append(str(o.get("tag", "")))
	if sim.jam_log.size() < 400:
		sim.jam_log.append({"cause": cause, "ids": chain, "kinds": kinds, "tags": tags, "pos": v["pos"], "t": sim.vt, "junction": VehicleRoads.junction_at_point(v["pos"])})
	if cause != "cycle":
		return
	var young: int = -1
	for id2 in cycle:
		young = maxi(young, int(id2))
	var yv: Dictionary = by_id(sim, young)
	if yv.is_empty() or yv.has("reverse_left"):
		return
	yv["reverse_left"] = minf(REVERSE_M, float(yv["s"]))
	sim.reversals += 1


## Backing up / waiting after it. Returns true when this step is used up by it.
static func hold(sim: VehicleSim, v: Dictionary, dt: float) -> bool:
	if v.has("reverse_left"):
		var step: float = REVERSE_SPEED * dt
		if _rear_blocked(sim, v) or float(v["s"]) <= 0.2:
			v.erase("reverse_left")
			v["wait_until"] = sim.vt + 1.5
			return true
		var path: VehiclePath = v["path"]
		v["s"] = maxf(float(v["s"]) - step, 0.0)
		v["reverse_left"] = float(v["reverse_left"]) - step
		v["v"] = 0.0
		v["pos"] = VehicleSim.centre(path, float(v["s"]), float(v["len"]))
		v["dir"] = VehicleSim.heading(path, float(v["s"]), float(v["len"]))
		if float(v["reverse_left"]) <= 0.0:
			v.erase("reverse_left")
			v["wait_until"] = sim.vt + WAIT_AFTER_S
		return true
	if sim.vt < float(v.get("wait_until", -1.0)):
		v["v"] = 0.0
		return true
	v.erase("wait_until")
	return false


static func _rear_blocked(sim: VehicleSim, v: Dictionary) -> bool:
	var h: Vector2 = v["dir"]
	var rt: Vector2 = VehicleRoads.right_of(h)
	for o in sim.vehicles:
		if o == v or str(o["state"]) == "dead":
			continue
		var d: Vector2 = (o["pos"] as Vector2) - (v["pos"] as Vector2)
		var along: float = d.dot(h)
		if along < 0.0 and -along < (float(v["len"]) + float(o["len"])) * 0.5 + 1.6 and absf(d.dot(rt)) < (float(v["wid"]) + float(o["wid"])) * 0.5:
			return true
	for p in sim.folks:
		var d2: Vector2 = p - (v["pos"] as Vector2)
		if d2.dot(h) < 0.0 and -d2.dot(h) < float(v["len"]) * 0.5 + 1.5 and absf(d2.dot(rt)) < float(v["wid"]) * 0.5 + 0.4:
			return true
	return false
