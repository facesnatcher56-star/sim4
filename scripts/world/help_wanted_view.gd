class_name HelpWantedView
extends Node3D
## Task 51: a "Help wanted" card in the front window of every business that has an opening this week (JobLeads.hiring_at), beside its front door
## (StaffPosts.front). View only: every few seconds it adds or removes the cards to match. Text and colours: data/job_leads.json "sign".

const SYNC_EVERY := 3.0

var _signs: Dictionary = {}          # lot id -> Node3D
var _t: float = 0.0
var _card_mat: StandardMaterial3D = null

static func ensure_on(lv: Node3D) -> HelpWantedView:
	var existing = lv.get_node_or_null("HelpWantedView")
	if existing != null:
		return existing
	var v := HelpWantedView.new()
	v.name = "HelpWantedView"
	lv.add_child(v)
	return v

func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = SYNC_EVERY
	sync_now()

func sign_count() -> int:
	return _signs.size()

func sync_now() -> void:
	var want: Dictionary = {}
	for lot in Neighborhood.lot_ids():
		if not JobLeads.hiring_at(str(lot)).is_empty() and not StaffPosts.front(str(lot)).is_empty():
			want[str(lot)] = true
	for lot2 in _signs.keys():
		if not want.has(lot2):
			(_signs[lot2] as Node).queue_free()
			_signs.erase(lot2)
	for lot3 in want:
		if not _signs.has(lot3):
			_signs[lot3] = _make(StaffPosts.front(lot3))
			add_child(_signs[lot3])

func _make(fr: Dictionary) -> Node3D:
	var sc: Dictionary = JobLeads.cfg().get("sign", {})
	var inward: Vector2 = Vector2(fr["inward"])
	var side := Vector2(-inward.y, inward.x)
	var spot: Vector2i = _window_by(fr)
	var c: Vector2 = Vector2(spot) + Vector2(0.5, 0.5) - inward * 0.68 + (Vector2.ZERO if spot != Vector2i(fr["door"]) else side * 1.1)
	var root := Node3D.new()
	root.position = Vector3(c.x, 1.25, c.y)
	root.rotation.y = atan2(-inward.x, -inward.y)          # face the street
	if _card_mat == null:
		_card_mat = StandardMaterial3D.new()
		_card_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_card_mat.albedo_color = Color(str(sc.get("card", "#f3efe4")))
		_card_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var card := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.5, 0.5)
	card.mesh = q
	card.material_override = _card_mat
	card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(card)
	var rim := MeshInstance3D.new()          # a red border, so the card reads as a sign from the street camera
	var q2 := QuadMesh.new()
	q2.size = q.size + Vector2(0.1, 0.1)
	rim.mesh = q2
	rim.material_override = _rim_mat(Color(str(sc.get("color", "#b3261e"))))
	rim.position = Vector3(0, 0, -0.01)
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(rim)
	var l := Label3D.new()
	l.text = str(sc.get("text", "HELP WANTED"))
	l.font_size = 64
	l.pixel_size = 0.0033
	l.modulate = Color(str(sc.get("color", "#b3261e")))
	l.outline_size = 10          # same colour: thicker letters that still read from the street camera
	l.outline_modulate = l.modulate
	l.double_sided = false
	l.shaded = false
	l.position = Vector3(0, 0, 0.01)
	root.add_child(l)
	return root

func _rim_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED          # unshaded: the card stays bright at night, like a lit window
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

## The ground-floor window in the same front wall nearest the door (the card goes in it); the door tile itself when there is none.
func _window_by(fr: Dictionary) -> Vector2i:
	var door: Vector2i = fr["door"]
	var inward: Vector2i = fr["inward"]
	var w = WorldIface.world()
	var best: Vector2i = door
	var bd: int = 1 << 30
	if w == null:
		return door
	for o in w.objects_of_def("window"):
		if ("level" in o and int(o.level) != 0):
			continue
		var dv: Vector2i = o.tile - door
		var along: int = absi(dv.x) if inward.x == 0 else absi(dv.y)
		var across: int = dv.y if inward.x == 0 else dv.x
		if across == 0 and along > 0 and along <= 4 and along < bd:
			bd = along
			best = o.tile
	return best
