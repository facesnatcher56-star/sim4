class_name VehicleRoutes
extends RefCounted
## Builds the paths of the vehicle layer from lot to lot: out of a bay (or a station apron), through the gate, onto the lane in front of the lot,
## along the street grid (VehicleRoads) and into the bay (or the curb stop) at the other end. Returns {path, visits, pickup_s, drop_s, pickup_door, drop_door}.
## Pure functions over the layout and the bays: no sim state.

const OUT_X := 4.5          # tiles west of the gate where a vehicle has joined the lane
const IN_X := 4.5           # tiles east of the gate where a vehicle that is about to turn in is in the lane
const GATE_LANE := 0.9      # the gate is two lanes: leaving on the west half, coming in on the east half (keep right)
const STOP_X := 3.2         # the pick-up / drop-off stop is this far from the gate along the lane


static func cfg() -> Dictionary:
	return SysUtil.table("vehicles")


static func _lane() -> float:
	return float(cfg().get("lane", 1.0))


static func _radius() -> float:
	return float(cfg().get("corner_radius", 1.8))


## From `a` (frontage dict) starting at `a_pos` (a bay centre, or Vector2.ZERO for the lane itself) to `b` ending in `b_pos` (a bay centre or ZERO for the lane).
## `pre` / `post` ({pts, visits} from VehicleRoads.entry_route / exit_route) add a drive in from a road end of the map before the trip and a drive out to one after it
## (a taxi, a car with no bay to park in): nothing starts or ends on the picture.
static func trip(fa: Dictionary, a_pos: Vector2, fb: Dictionary, b_pos: Vector2, lead: float = 0.0, pre: Dictionary = {}, post: Dictionary = {}) -> Dictionary:
	if fa.is_empty() or fb.is_empty():
		return {}
	var ga: float = float(fa["gate"])
	var gb: float = float(fb["gate"])
	var pts: Array = []
	var pre_len: float = 0.0
	if not pre.is_empty():
		pts.append_array(pre["pts"])
		for k in range(1, pts.size()):
			pre_len += (pts[k] as Vector2).distance_to(pts[k - 1])
	if lead > 0.0:
		pts.append(Vector2(ga + lead, float(fa["lane_z"])))          # a vehicle that comes from up the street (a taxi)
	if a_pos != Vector2.ZERO:
		pts.append(a_pos)
		pts.append(Vector2(ga - GATE_LANE, a_pos.y))
	pts.append(Vector2(ga - GATE_LANE, float(fa["lane_z"])))
	var r: Dictionary = VehicleRoads.lane_route(fa, ga - OUT_X, fb, gb + IN_X, _lane())
	pts.append_array(r["pts"])
	pts.append(Vector2(gb + GATE_LANE, float(fb["lane_z"])))
	if b_pos != Vector2.ZERO:
		pts.append(Vector2(gb + GATE_LANE, b_pos.y))
		pts.append(b_pos)
	var post_pts: Array = []
	if not post.is_empty():
		post_pts = post["pts"]
		for k2 in range(1, post_pts.size()):
			pts.append(post_pts[k2])
	var path: VehiclePath = VehiclePath.make(pts, _radius())
	var s_pick: float = path.closest_s(Vector2(ga - STOP_X, float(fa["lane_z"])), maxf(pre_len - 4.0, 0.0), 90.0)
	var s_drop: float = path.closest_s(Vector2(gb + STOP_X, float(fb["lane_z"])), s_pick + 1.0, 400.0)
	var gate_y: Dictionary = {}
	if a_pos != Vector2.ZERO:
		gate_y = {"s": 0.3, "x": ga, "z": float(fa["lane_z"]), "hy": float(fa["hy"]), "rect": VehicleAmbient.yard_rect(fa)}      # wait in the bay, not in the walkway, until the way out is clear
	var vis: Array = []
	if not pre.is_empty():
		vis.append_array(pre["visits"])
	vis.append_array(r["visits"])
	if not post.is_empty():
		vis.append_array(post["visits"])
	return {"path": path, "visits": vis, "gate_yield": gate_y, "pickup_s": s_pick, "drop_s": s_drop,
		"pickup_door": Vector2(ga - STOP_X, float(fa["hy"]) + 0.5), "drop_door": Vector2(gb + STOP_X, float(fb["hy"]) + 0.5)}


## Out of a station and back, with a stop at the call: lane stop at `b`, then home again. `hold_s` is the pause (vehicle seconds) at the scene.
static func round_trip(fs: Dictionary, fb: Dictionary) -> Dictionary:
	var out: Dictionary = trip(fs, Vector2(float(fs["gate"]), float(fs["hy"]) - 3.0), fb, Vector2.ZERO)
	if out.is_empty():
		return {}
	var gb: float = float(fb["gate"])
	var back: Dictionary = VehicleRoads.lane_route(fb, gb - 1.0, fs, float(fs["gate"]) + IN_X, _lane())
	var pts: Array = []
	var op: VehiclePath = out["path"]
	pts.append_array(op.pts)
	pts.append_array(back["pts"])
	pts.append(Vector2(float(fs["gate"]), float(fs["lane_z"])))
	pts.append(Vector2(float(fs["gate"]), float(fs["hy"]) - 3.0))
	var path: VehiclePath = VehiclePath.make(pts, 0.0)       # the pieces are already rounded: only the seams remain
	var s_scene: float = path.closest_s(Vector2(gb + STOP_X, float(fb["lane_z"])), 0.0, op.length + 8.0)
	var visits: Array = (out["visits"] as Array).duplicate()
	visits.append_array(back["visits"])
	return {"path": path, "visits": visits, "scene_s": s_scene, "out_len": op.length}
