class_name ClutterView
extends Node3D
## Task 41a (view only; reads World.mess and the lots' poverty, never writes): floor clutter that BUILDS UP with a room's mess and goes when it is tidied.
## Dishes, clothes, boxes, bags, bottles and paper appear on indoor tiles with mess (more pieces per level: untidy 1, messy 2, squalid 4, data/wear_layer.json), the
## kind follows the room (kitchen dishes, bedroom clothes ...), and a poor lot also shows a few boxes and bags that do not go away with a tidy-up.
## Pieces are tile-hash placed (WearRules.clutter_for_tile): the same mess always shows the same pieces. One MultiMesh per kind: a handful of draw calls for the
## whole map. Re-read twice a second when the mess table or a lot's poverty changed (never per frame). Tiles with an object on them stay clear.

const POLL_SEC := 0.5
const NEAR_MAX := 90.0            # metres from the camera target; farther pieces are skipped (they are 10 cm props)

var lot = null
var _sig := -1
var _t := 0.0
var _kinds_cache: Dictionary = {}     # room id -> kind
var count := 0                        # pieces currently drawn (tests, perf notes)


static func ensure_on(parent: Node) -> ClutterView:
	var n := parent.get_node_or_null("ClutterView") as ClutterView
	if n == null:
		n = ClutterView.new()
		n.name = "ClutterView"
		n.lot = parent
		parent.add_child(n)
		World.world_reset.connect(n.refresh)
		WearLayer.bus.changed.connect(func(_l): n.refresh())
	return n


func refresh() -> void:
	_sig = -1
	_kinds_cache.clear()
	_t = 0.0
	_poll()


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = POLL_SEC
	_poll()


func _poll() -> void:
	var sig := World.mess.hash() ^ (World.objects.size() * 31) ^ int(WearLayer.lot_poverty(Neighborhood.HOME) * 100.0)
	if sig == _sig:
		return
	_sig = sig
	rebuild()


func rebuild() -> void:
	var old := get_node_or_null("Pieces")
	if old != null:
		remove_child(old)
		old.queue_free()
	var tiles: Dictionary = {}                      # tile -> mess
	for t in World.mess:
		if float(World.mess[t]) >= 0.01:
			tiles[t] = float(World.mess[t])
	for lot_id in _poor_lots():                     # poverty baseline: scan the lot's rect once per change
		var rc := NeighborhoodLots.rect_of(lot_id)
		for y in range(rc.position.y, rc.end.y):
			for x in range(rc.position.x, rc.end.x):
				var t := Vector2i(x, y)
				if not tiles.has(t):
					tiles[t] = 0.0
	var placements: Array = []
	for t in tiles:
		if World.object_at(t) != null or World.rooms.is_outdoor(t):
			continue
		var pov := WearLayer.poverty_at(t)
		var pieces := WearRules.clutter_for_tile(t, float(tiles[t]), _room_kind(t), pov)
		for p in pieces:
			placements.append({"kind": p["kind"], "pos": Vector3(t.x + float(p["ox"]), 0.02, t.y + float(p["oz"])), "yaw": p["yaw"], "scale": p["scale"], "tone": p["tone"]})
	count = placements.size()
	var root := WearProps.build(self, placements, "Pieces", NEAR_MAX)
	root.name = "Pieces"


func _poor_lots() -> Array:
	var out: Array = []
	var min_p := float(((WearRules.cfg().get("mess", {}) as Dictionary).get("poverty_baseline", {}) as Dictionary).get("min_poverty", 0.6))
	for id in _lot_ids():
		if WearLayer.lot_poverty(id) >= min_p:
			out.append(id)
	return out


func _lot_ids() -> Array:
	var ids: Array = []
	if World.regions.has_regions():
		for rid in World.regions.regions:
			if World.regions.is_lot(rid):
				ids.append(str(World.regions.regions[rid].get("lot", "")))
	else:
		ids.append(Neighborhood.HOME)
	return ids


## Room kind from what stands in it: kitchen / bathroom / bedroom / living (WearRules kinds_by_room keys).
func _room_kind(t: Vector2i) -> String:
	var info: Dictionary = World.rooms.room_info(t)
	if info.is_empty():
		return "default"
	var rid: int = int(info["id"])
	if _kinds_cache.has(rid):
		return _kinds_cache[rid]
	var kind := "living"
	var score := {"kitchen": 0, "bathroom": 0, "bedroom": 0}
	for oid in info["objects"]:
		var o = World.get_object(int(oid))
		if o == null:
			continue
		match str(o.def_id):
			"stove", "fridge", "counter", "microwave_cart", "coffee_maker", "sink":
				score["kitchen"] += 1
			"toilet", "shower", "bathtub":
				score["bathroom"] += 2
			"bed", "single_bed", "dresser", "wardrobe", "nightstand", "crib", "bunk_bed":
				score["bedroom"] += 1
	var best := 0
	for k in score:
		if score[k] > best:
			best = score[k]
			kind = k
	_kinds_cache[rid] = kind
	return kind
