class_name ProgressLayer
extends Control
## Task 33.4 (view only): the little progress ring above a folk's head while a timed action runs (fills toward done, the action's icon inside). Which folk get one is
## the Settings choice `progress_rings` (ProgressRing.shows_for); the selected folk always counts unless it is Off. The list of candidates is rebuilt a few times a
## second, the ring itself is redrawn per frame from `Interaction.progress()`. Nothing is written to the sim. Reduce motion: no easing, the ring just jumps to the value.
## Rings keep clear of the name tag and the mood icon (`place_clear`) and `rects()` lets ThoughtLayer put its balloons above them.

const SCAN_SEC := 0.25

var lot_view = null
var selected_id := -1                 # kept by Hud.select_folk
var _rings: Array = []                # {id, inter, pos, frac, shape, color}
var _scan_t := 0.0
var _shown: Dictionary = {}           # folk id -> displayed fraction (eased)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Folk that get a ring right now, as [{id, inter}] (pure read of the world).
static func candidates(mode: int, selected_id: int, max_everyone: int = 14) -> Array:
	var out: Array = []
	if mode == ProgressRing.OFF:
		return out
	var sel_hh := -1
	var sel = World.get_folk(selected_id) if selected_id >= 0 else null
	if sel != null:
		sel_hh = int(sel.household_id)
	for f in World.all_folk():
		var cur = f.current
		if cur == null or ProgressRing.fraction(cur) < 0.0:
			continue
		if not ProgressRing.shows_for(mode, int(f.id), int(f.household_id), selected_id, sel_hh):
			continue
		out.append({"id": int(f.id), "inter": cur})
		if mode == ProgressRing.EVERYONE and out.size() >= max_everyone:
			break
	return out


func _process(delta: float) -> void:
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = SCAN_SEC
		_refresh_candidates()
	_update_rings(delta)
	queue_redraw()


var _cands: Array = []


func _refresh_candidates() -> void:
	_cands = candidates(GameSettings.progress_rings_mode(), selected_id, int(ProgressRing.cfg().get("max_everyone", 14)))


func _update_rings(delta: float) -> void:
	_rings.clear()
	if lot_view == null or not lot_view.has_method("screen_pos"):
		return
	var cfg := ProgressRing.cfg()
	var rad := float(cfg.get("radius_px", 13.0))
	var live: Dictionary = {}
	for c in _cands:
		var inter = c["inter"]
		var frac: float = ProgressRing.fraction(inter)
		if frac < 0.0:
			continue
		var fv = lot_view.call("get_folk_view", c["id"]) if lot_view.has_method("get_folk_view") else null
		if fv == null or not fv.visible:
			continue
		var cam = lot_view.get("_cam")
		if cam == null:
			continue
		var head: Vector3 = fv.head_position()
		if cam.is_position_behind(head):
			continue
		# sits just above the head, then is pushed up until it clears the name tag and the mood icon (both are 3D nodes on the folk)
		var center: Vector2 = cam.unproject_position(head + Vector3(0, -0.15, 0)) - Vector2(0, rad + 4.0)
		var obstacles: Array = []
		if bool(fv.show_name):
			var nw := 13.0 * str(World.get_folk(c["id"]).name).length() + 14.0
			var nc: Vector2 = cam.unproject_position(fv.global_position + Vector3(0, 2.0, 0))
			obstacles.append(Rect2(nc - Vector2(nw * 0.5, 15.0), Vector2(nw, 30.0)))
		if fv._mood_icon != null and fv._mood_icon.visible:
			var mc: Vector2 = cam.unproject_position(head + Vector3(0, 0.28, 0))
			obstacles.append(Rect2(mc - Vector2(13, 13), Vector2(26, 26)))
		var pos := place_clear(center, rad + 3.0, obstacles)
		var shown: float = frac
		if not GameSettings.reduce_motion() and _shown.has(c["id"]):
			shown = lerpf(float(_shown[c["id"]]), frac, clampf(delta * 10.0, 0.0, 1.0))
		_shown[c["id"]] = shown
		live[c["id"]] = true
		var tags: Array = inter.def.get("tags", []) if inter.def is Dictionary else []
		var icon := ProgressRing.icon_for(str(inter.def_id), tags)
		_rings.append({"id": c["id"], "pos": pos,
			"frac": shown, "shape": str(icon.get("shape", "dots")), "color": Color(str(icon.get("color", "#e6edf5"))), "r": rad})
	for id in _shown.keys():
		if not live.has(id):
			_shown.erase(id)


## Moves a ring centre straight up until a circle of radius `r` no longer touches any obstacle rect (name tag, mood icon).
static func place_clear(center: Vector2, r: float, obstacles: Array) -> Vector2:
	var p := center
	for i in 8:
		var moved := false
		for o in obstacles:
			var rect: Rect2 = o
			if Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0).intersects(rect):
				p.y = rect.position.y - r - 2.0
				moved = true
		if not moved:
			break
	return p


## Screen rects of the rings drawn this frame (for ThoughtLayer to keep balloons clear).
func rects() -> Array:
	var out: Array = []
	for r in _rings:
		var rr: float = float(r["r"]) + 3.0
		out.append(Rect2(r["pos"] - Vector2(rr, rr), Vector2(rr, rr) * 2.0))
	return out


func _draw() -> void:
	for r in _rings:
		var c: Vector2 = r["pos"]
		var rad: float = r["r"]
		draw_circle(c, rad + 2.0, Color(0.06, 0.08, 0.12, 0.82))
		draw_arc(c, rad - 1.5, 0.0, TAU, 32, Color(1, 1, 1, 0.18), 3.0, true)
		var f: float = r["frac"]
		if f > 0.004:
			draw_arc(c, rad - 1.5, -PI * 0.5, ProgressRing.arc_end(f), 32, UITheme.ACCENT, 3.5, true)
		ProgressIcons.draw(self, str(r["shape"]), c, rad * 0.62, r["color"])
