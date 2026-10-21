class_name VehiclePlaces
extends RefCounted
## Geometry of getting into and out of a parking place (task 42), pure functions over a place of VehicleBays and the frontage of its lot (VehicleRoads.frontage).
## Cause: a car turns in from the lane where the place is, nose first (driveway, bay: straight in from the lane; lay-by: a diagonal into the parallel bay) and leaves the way it
## came: backing out of a driveway or bay (the first `back_m` metres the body points the way it came), driving out of a lay-by. The lane in front of every lot flows west.
##   in_x(place) / out_x(place)   x on the lane where the route to / from the place meets it       in_mid / out_mid(place) -> [Vector2]   points between the lane and the place
##   back_m(place, fr)            reversing distance of the way out       yard_rect(place)       door_of(lot_id)       side_of(place) -> where the driver stands

const LANE_RUN := 3.0          # straight metres of lane before the turn in / after the turn out


static func in_x(pl: Dictionary) -> float:
	if str(pl["kind"]) == "layby":
		return (pl["pos"] as Vector2).x + 4.5
	return (pl["pos"] as Vector2).x


static func out_x(pl: Dictionary) -> float:
	if str(pl["kind"]) == "layby":
		return (pl["pos"] as Vector2).x - 4.5
	return (pl["pos"] as Vector2).x


static func in_mid(pl: Dictionary) -> Array:
	var p: Vector2 = pl["pos"]
	return [Vector2(p.x + 2.0, p.y)] if str(pl["kind"]) == "layby" else []


static func out_mid(pl: Dictionary) -> Array:
	var p: Vector2 = pl["pos"]
	return [Vector2(p.x - 2.0, p.y)] if str(pl["kind"]) == "layby" else []


const AXLE := 0.84             # a 4.2 m body is drawn between the points 1.68 m behind and ahead of its path distance: its centre trails the path point by this much

## Last point of the way in: the body centre comes to rest on `pos`.
static func arrive_pt(pl: Dictionary) -> Vector2:
	return (pl["pos"] as Vector2) + (pl["face"] as Vector2).normalized() * AXLE


## First point of the way out: the body centre starts on `pos`.
static func depart_pt(pl: Dictionary, lane_z: float) -> Vector2:
	var p: Vector2 = pl["pos"]
	var mid: Array = out_mid(pl)
	var nxt: Vector2 = mid[0] if not mid.is_empty() else Vector2(out_x(pl), lane_z)
	return p - (nxt - p).normalized() * AXLE


## Metres of the way out driven backwards: to the kerb line in front of a driveway or bay.
static func back_m(pl: Dictionary, fr: Dictionary) -> float:
	if not bool(pl.get("back", false)):
		return 0.0
	return maxf((float(fr["hy"]) + 0.6) - (pl["pos"] as Vector2).y, 0.0)


## The area one moving car needs (the place plus the verge strip to the lane): one car moves about in it at a time.
static func yard_rect(pl: Dictionary) -> Rect2:
	var rc: Rect2 = pl["rect"]
	return Rect2(rc.position.x - 0.3, rc.position.y - 0.5, rc.size.x + 0.6, rc.size.y + 3.5)


static func side_of(pl: Dictionary) -> Vector2:
	var p: Vector2 = pl["pos"]
	if str(pl["kind"]) == "layby":
		return p + Vector2(0.0, -1.5)
	return p + Vector2(1.6, 0.0)


## Where the people of a lot come from and go to: the walk spot (door side) of the lot.
static func door_of(lot_id: String) -> Vector2:
	var t: Vector2i = MapLots.walk_spot(lot_id)
	return Vector2(float(t.x) + 0.5, float(t.y) + 0.5)
