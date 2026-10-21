extends RefCounted
## Task 41 part C (fast): furniture and vehicle recolouring. Per-object wear palettes (worn wood, faded fabric, scuffed metal, dull car paint with dirt or
## rust), driven by a deterministic age (id hash + wealth tier of the price). Reference stays untouched.

var fails: Array = []


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func run() -> Array:
	fails = []
	var start: String = Looks.current_id()
	LookKits.clear_cache()
	# --- data
	var kc: Dictionary = Looks.data().get("kit_class", {})
	var kits: Dictionary = Looks.look("grounded").get("kits", {})
	_check(Looks.look("reference").get("kits", {"x": 1}).is_empty(), "reference has no kit recolouring")
	for m in kc:
		_check(kits.has(kc[m]), "kit class %s (material %s) has a grounded palette" % [kc[m], m])
	for c in ["wood", "fabric", "metal", "enamel", "paint", "brass", "book", "carpaint"]:
		_check(kits.has(c), "grounded has a %s palette" % c)
	_check(LookKits.class_of("headlight") == "" and LookKits.class_of("glass") == "" and LookKits.class_of("tyre") == "" and LookKits.class_of("skin") == "", "lights, glass, tyres and skin are never recoloured")
	# --- colour rules
	Looks.set_look("grounded")
	var wood := Color(0.55, 0.36, 0.2)
	var nice := LookKits.colour("wood", wood, 0, "dirt")
	var used := LookKits.colour("wood", wood, 1, "dirt")
	var worn := LookKits.colour("wood", wood, 2, "dirt")
	_check(nice.v > used.v and used.v > worn.v, "wood gets darker with wear (%.2f > %.2f > %.2f)" % [nice.v, used.v, worn.v])
	_check(nice.s < wood.s and worn.s < nice.s, "wood fades with wear")
	var fab := Color(0.7, 0.25, 0.25)
	_check(LookKits.colour("fabric", fab, 2, "dirt").s < LookKits.colour("fabric", fab, 0, "dirt").s * 0.8, "fabric fades with wear")
	var body := Color(0.2, 0.4, 0.8)
	var clean := LookKits.colour("carpaint", body, 0, "rust")
	_check(clean.is_equal_approx(LookKits.colour("carpaint", body, 0, "dirt")), "a nice car has no rust or dirt")
	var rust := LookKits.colour("carpaint", body, 2, "rust")
	var dirt := LookKits.colour("carpaint", body, 2, "dirt")
	_check(rust.r > rust.b and not rust.is_equal_approx(dirt), "a worn car shows rust or dirt (two variants)")
	_check(LookKits.colour("carpaint", body, 0, "dirt").s < body.s, "car paint is dull even when nice")
	_check(LookKits.colour("wood", wood, 2, "dirt") == LookKits.colour("wood", wood, 2, "dirt"), "colour is pure / deterministic")
	Looks.set_look("reference")
	_check(LookKits.colour("wood", wood, 2, "dirt") == wood, "reference leaves colours alone")
	Looks.set_look("grounded")
	# --- age / wealth tiers
	_check(LookKits.age(5, "chair", 80.0) == LookKits.age(5, "chair", 80.0), "age is deterministic")
	var cheap := 0.0
	var rich := 0.0
	var worn_cheap := 0
	var worn_rich := 0
	for id in range(1, 301):
		var a1 := LookKits.age(id, "chair", 60.0)
		var a2 := LookKits.age(id, "chair", 1800.0)
		cheap += a1
		rich += a2
		worn_cheap += 1 if LookKits.bucket(a1) == 2 else 0
		worn_rich += 1 if LookKits.bucket(a2) == 2 else 0
	_check(cheap > rich + 30.0, "cheap objects are older on average (%.2f vs %.2f)" % [cheap / 300.0, rich / 300.0])
	_check(worn_cheap > worn_rich * 2, "cheap objects are worn far more often (%d vs %d of 300)" % [worn_cheap, worn_rich])
	_check(LookKits.age(1, "x", 10.0) >= 0.0 and LookKits.age(1, "x", 10.0) <= 1.0, "age stays in 0..1")
	var v := {"rust": 0, "dirt": 0}
	for id in range(1, 200):
		v[LookKits.variant_of(id)] += 1
	_check(v["rust"] > 60 and v["dirt"] > 60, "cars split between rust and dirt (%s)" % str(v))
	# --- real glbs
	var ps := load("res://assets/models/armchair.glb") as PackedScene
	_check(ps != null, "armchair glb loads")
	if ps != null:
		Looks.set_look("reference")
		var r := ps.instantiate()
		var before := _first_colour(r)
		LookKits.apply(r, 3, "armchair", 320.0)
		_check(_first_colour(r) == before and not r.has_meta("kitted"), "reference leaves the model alone")
		r.free()
		Looks.set_look("grounded")
		var a := ps.instantiate()
		var b := ps.instantiate()
		var c0 := _first_colour(a)
		# find an id that lands in the worn bucket and one in the nice bucket
		var worn_id := -1
		var nice_id := -1
		for id in range(1, 400):
			var bk := LookKits.bucket(LookKits.age(id, "armchair", 60.0))
			if bk == 2 and worn_id < 0:
				worn_id = id
			var bk2 := LookKits.bucket(LookKits.age(id, "armchair", 1800.0))
			if bk2 == 0 and nice_id < 0:
				nice_id = id
		LookKits.apply(a, worn_id, "armchair", 60.0)
		LookKits.apply(b, nice_id, "armchair", 1800.0)
		var ca := _first_colour(a)
		var cb := _first_colour(b)
		_check(ca != c0 and cb != c0, "grounded recolours the armchair model")
		_check(ca.v < cb.v, "the worn armchair is darker than the nice one (%.2f < %.2f)" % [ca.v, cb.v])
		_check(_names_kept(a), "material names survive the recolour (state visuals match on them)")
		LookKits.apply(a, 99, "armchair", 60.0)
		_check(_first_colour(a) == ca, "apply is idempotent per node")
		var shared := ps.instantiate()
		LookKits.apply(shared, worn_id, "armchair", 60.0)
		_check(_first_mesh(shared) == _first_mesh(a), "same object condition shares one tinted mesh (no per-object copies)")
		a.free()
		b.free()
		shared.free()
		# a vehicle
		var car := load("res://assets/models/outdoor/car_sedan_blue.glb") as PackedScene
		if car != null:
			var ci := car.instantiate()
			var cc0 := _colour_of(ci, "body")
			LookKits.apply(ci, 11, "car_sedan_blue", 300.0)
			var cc1 := _colour_of(ci, "body")
			_check(cc1 != cc0 and cc1.s < cc0.s, "grounded dulls the car paint (s %.2f -> %.2f)" % [cc0.s, cc1.s])
			var plain := car.instantiate()
			_check(_colour_of(ci, "headlight") == _colour_of(plain, "headlight"), "headlights keep their colour")
			plain.free()
			ci.free()
	LookKits.clear_cache()
	Looks.set_look(start)
	return fails


func _meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		_meshes(c, out)


func _first_mesh(n: Node) -> Mesh:
	var l: Array = []
	_meshes(n, l)
	return (l[0] as MeshInstance3D).mesh if not l.is_empty() else null


func _first_colour(n: Node) -> Color:
	var l: Array = []
	_meshes(n, l)
	for mi in l:
		for s in (mi as MeshInstance3D).mesh.get_surface_count():
			var m := (mi as MeshInstance3D).mesh.surface_get_material(s) as BaseMaterial3D
			if m != null and LookKits.class_of(m.resource_name) != "":
				return m.albedo_color
	return Color.BLACK


func _colour_of(n: Node, mname: String) -> Color:
	var l: Array = []
	_meshes(n, l)
	for mi in l:
		for s in (mi as MeshInstance3D).mesh.get_surface_count():
			var m := (mi as MeshInstance3D).mesh.surface_get_material(s) as BaseMaterial3D
			if m != null and m.resource_name == mname:
				return m.albedo_color
	return Color.BLACK


func _names_kept(n: Node) -> bool:
	var l: Array = []
	_meshes(n, l)
	for mi in l:
		for s in (mi as MeshInstance3D).mesh.get_surface_count():
			var m := (mi as MeshInstance3D).mesh.surface_get_material(s) as BaseMaterial3D
			if m != null and m.resource_name == "":
				return false
	return true
