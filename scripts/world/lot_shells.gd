extends "res://scripts/world/lot_build.gd"
## LotView layer: building SHELLS. Seen from outside every building of the map (house, cafe, gym, ...) is a solid shell model
## (assets/models/outdoor/*.glb, nodes `body` + `roof`) scaled to the walls of its lot template, so lots are recognisable from
## afar. The shell of a building disappears (body and roof) as soon as a player Folk is inside or next to it; while it stands,
## the objects and Folk behind it are hidden. Build tools always open the home. `shells_enabled = false` shows every interior.
## The templates' door side is south and the models' door is on -Z, so shells are turned 180 degrees about Y.

const SHELL_DIR := "res://assets/models/outdoor/"
const SHELL_MARGIN := 0.12          # the shell is this much bigger on each side than the template walls (no z-fighting with them)
const OPEN_RADIUS := 2              # tiles around the building footprint that open the shell
const SHELL_PERIOD := 0.25          # seconds between occupancy checks
const SHELL_NAMES := {"small": "house_small_%s", "medium": "house_medium_%s", "classic": "house_medium_%s", "large": "house_large_%s",
	"cafe": "cafe_%s", "gym": "gym_%s", "library": "library_%s", "market": "market_%s", "school": "school_%s", "office": "office_%s"}

const OVERVIEW_ZOOM := 28.0        # zoomed out at least this far, a click on a lot flies the camera to it
const LOT_FRAME_ZOOM := 22.0

var shells_enabled: bool = true
var _shells: Dictionary = {}         # lot id -> {root: Node3D, rect: Rect2i (tiles), open: bool, lot: String}
var _shell_clock: float = 0.0


## Footprint of a lot's building in world tiles (Rect2i()) from its template; empty for open-air lots (park).
func _building_rect(region: Dictionary) -> Rect2i:
	var local := LotLoader.building_rect(str(region["template"]))
	if local.size == Vector2i.ZERO:
		return Rect2i()
	return Rect2i(local.position + (region["rect"] as Rect2i).position, local.size)


func _rebuild_shells() -> void:
	for sh in _shells.values():
		(sh["root"] as Node3D).queue_free()
	_shells.clear()
	if not World.regions.has_regions():
		return
	for r in World.regions.regions.values():
		if not World.regions.is_lot(int(r["id"])):
			continue
		var rect := _building_rect(r)
		var tid: String = str(r["template"])
		var key: String = tid if SHELL_NAMES.has(tid) else tid.split("_")[0]
		if rect.size == Vector2i.ZERO or not SHELL_NAMES.has(key):
			continue
		var variants: int = 3 if key in ["small", "medium", "large", "classic"] else 2
		var ps := _load_model(SHELL_DIR + (SHELL_NAMES[key] as String) % "abc"[absi(hash(str(r["lot"]))) % variants] + ".glb")
		if ps == null:
			continue
		var model: Node3D = ps.instantiate()
		var root := Node3D.new()
		root.name = "shell_%s" % str(r["lot"])
		var fp := _shell_footprint(key)
		var want := Vector2(rect.size) + Vector2.ONE * (SHELL_MARGIN * 2.0)
		root.position = Vector3(rect.position.x + rect.size.x * 0.5, 0.0, rect.position.y + rect.size.y * 0.5)
		root.rotation.y = PI
		model.scale = Vector3(want.x / fp.x, 1.0, want.y / fp.y)
		root.add_child(model)
		add_child(root)
		_shells[str(r["lot"])] = {"root": root, "rect": rect, "open": false, "lot": str(r["lot"]), "home": str(r["kind"]) == "home"}
	_shell_clock = SHELL_PERIOD


## Model footprint (w, d) in metres from the outdoor manifest ((10, 7) etc.).
func _shell_footprint(key: String) -> Vector2:
	match key:
		"small": return Vector2(10, 7)
		"medium", "classic": return Vector2(14, 11)
		"large": return Vector2(22, 14)
	return Vector2(22, 14)


func _update_shells(delta: float) -> void:
	_shell_clock += delta
	if _shell_clock < SHELL_PERIOD:
		return
	_shell_clock = 0.0
	var watchers: Array = []
	for f in World.all_folk():
		if int(f.household_id) > 0 and not f.has_meta("away") and not f.has_meta("visitor"):
			watchers.append(f.tile)
	var changed: Array = []
	for sh in _shells.values():
		var rect: Rect2i = sh["rect"]
		var open: bool = not shells_enabled or (bool(sh["home"]) and tool != "select")
		if not open:
			var near := rect.grow(OPEN_RADIUS)
			for t in watchers:
				if near.has_point(t):
					open = true
					break
		if open != bool(sh["open"]):
			sh["open"] = open
			(sh["root"] as Node3D).visible = not open
			changed.append(sh)
	for sh2 in changed:
		_set_interior_visible(sh2["rect"], bool(sh2["open"]))
	# Folk behind a standing shell are not drawn
	for fid in _folk_views:
		var fv: FolkView = _folk_views[fid]
		var f2 = World.get_folk(fid)
		if f2 == null:
			continue
		var hidden := false
		for sh3 in _shells.values():
			if not bool(sh3["open"]) and (sh3["rect"] as Rect2i).has_point(f2.tile):
				hidden = true
				break
		if hidden:
			fv.set_meta("occluded", true)
		elif fv.has_meta("occluded"):
			fv.remove_meta("occluded")


func _set_interior_visible(rect: Rect2i, on: bool) -> void:
	for oid in _obj_nodes:
		var o = World.get_object(oid)
		if o != null and rect.has_point(o.tile):
			(_obj_nodes[oid] as Node3D).visible = on


## Objects added later inside a standing shell stay hidden with it.
func _shell_hides(tile: Vector2i) -> bool:
	for sh in _shells.values():
		if not bool(sh["open"]) and (sh["rect"] as Rect2i).has_point(tile):
			return true
	return false


## Which standing shell (lot id) covers this tile ("" none).
func shell_lot_at(tile: Vector2i) -> String:
	for sh in _shells.values():
		if not bool(sh["open"]) and (sh["rect"] as Rect2i).has_point(tile):
			return str(sh["lot"])
	return ""


## Zoomed-out overview: a click on a lot centres the camera on it and zooms in to frame it (instead of picking a thing).
func _on_left_press(mp: Vector2) -> void:
	if tool == "select" and _zoom_target >= OVERVIEW_ZOOM and World.regions.has_regions():
		var lot := Neighborhood.lot_at(tile_at_screen(mp))
		if lot != "":
			Neighborhood.focus_lot(lot)
			set_zoom(LOT_FRAME_ZOOM)
			return
	super(mp)
