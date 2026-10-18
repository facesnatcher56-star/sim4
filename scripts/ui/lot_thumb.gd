class_name LotThumb
extends Control
## Floor-plan thumbnail of a lot template (set `template_id`, give it a minimum size). Used by the new-game cards.

# Hand-drawn plan of the classic starter house (floors + walls).
const CLASSIC_FLOORS := [[4, 4, 9, 9, "carpet"], [10, 4, 13, 9, "tile"], [14, 4, 19, 9, "carpet"], [4, 10, 10, 15, "tile"],
	[11, 10, 19, 15, "wood"], [15, 16, 15, 20, "stone"]]
const CLASSIC_WALLS := [[4, 4, 20, 4], [4, 16, 20, 16], [4, 4, 4, 16], [20, 4, 20, 16], [4, 10, 20, 10], [10, 4, 10, 10], [14, 4, 14, 10], [11, 10, 11, 16]]

var template_id: String = "classic"
const FLOOR_COLORS := {"grass": "#4f7d3f", "dirt": "#7a5c3b", "stone": "#8a8a8a", "concrete": "#6f7478", "wood": "#a9794a", "tile": "#c3d2da", "carpet": "#7a6290"}

func _draw() -> void:
	var s: Vector2 = size
	var ws := Vector2(32, 24)
	var k: float = minf(s.x / ws.x, s.y / ws.y)
	draw_set_transform((s - ws * k) * 0.5)      # centred in the control
	draw_rect(Rect2(Vector2.ZERO, ws * k), Color(FLOOR_COLORS["grass"]))
	var floors: Array = []
	var walls: Array = []
	var objs: Array = []
	if template_id == "classic":
		for f in CLASSIC_FLOORS:
			floors.append({"rect": [f[0], f[1], f[2], f[3]], "type": f[4]})
		for w in CLASSIC_WALLS:
			walls.append({"a": [w[0], w[1]], "b": [w[2], w[3]], "type": "wall"})
		walls.append({"a": [2, 2], "b": [30, 2], "type": "fence"})
		walls.append({"a": [30, 2], "b": [30, 22], "type": "fence"})
		walls.append({"a": [2, 22], "b": [30, 22], "type": "fence"})
		walls.append({"a": [2, 2], "b": [2, 22], "type": "fence"})
	else:
		var t: Dictionary = LotLoader.template(template_id)
		floors = t.get("floors", [])
		walls = t.get("walls", [])
		objs = t.get("objects", [])
	for fl in floors:
		var r: Array = fl["rect"]
		draw_rect(Rect2(Vector2(r[0], r[1]) * k, Vector2(r[2] - r[0] + 1, r[3] - r[1] + 1) * k), Color(FLOOR_COLORS.get(str(fl["type"]), "#888888")))
	for o in objs:
		var d: String = str(o["def"])
		if d == "door" or d == "window":
			continue
		var p := Vector2(o["tile"][0], o["tile"][1]) * k
		draw_rect(Rect2(p + Vector2(1, 1), Vector2(k - 2, k - 2)), Color(0.22, 0.2, 0.18, 0.85))
	for wl in walls:
		var a := Vector2(wl["a"][0], wl["a"][1]) * k
		var b := Vector2(wl["b"][0], wl["b"][1]) * k
		var fence: bool = str(wl["type"]) == "fence"
		draw_line(a, b, Color("#d9c9a8") if fence else Color("#f1ece2"), 1.0 if fence else 2.5)
	draw_rect(Rect2(Vector2.ZERO, ws * k), Color(1, 1, 1, 0.12), false, 1.0)
