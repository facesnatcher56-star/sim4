extends RefCounted
## Task 41 (fast): data/looks.json has the looks with every required key, `reference` equals the values it replaced, a runtime look switch
## changes tints and is reversible, the Settings dropdown matches the data, and no sim state is touched.

var fails: Array = []


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func run() -> Array:
	fails = []
	var ids: Array = Looks.ids()
	_check("reference" in ids and "grounded" in ids, "looks.json lists reference and grounded")
	_check(str(Looks.data().get("default", "")) == "reference", "default look is reference")
	for id in ids:
		var l: Dictionary = Looks.look(id)
		_check(not l.is_empty(), "look %s exists" % id)
		for s in Looks.SURFACES:
			_check((l.get("surfaces", {}) as Dictionary).has(s), "%s surface %s" % [id, s])
		for k in Looks.ENV_KEYS:
			_check((l.get("env", {}) as Dictionary).has(k), "%s env %s" % [id, k])
		for k in Looks.UI_KEYS:
			_check((l.get("ui", {}) as Dictionary).has(k), "%s ui %s" % [id, k])
		for k in Looks.WEAR_KEYS:
			_check((l.get("wear", {}) as Dictionary).has(k), "%s wear %s" % [id, k])
		_check(l.has("palette") and str(l.get("label", "")) != "", "%s palette and label" % id)
	# the Settings dropdown lists exactly the looks of the data
	var opts: Array = GameSettings.def_of("visual_style").get("opts", [])
	_check(opts.map(func(o): return o[0]) == ids, "Settings visual_style options match looks.json")
	# reference = today's values
	var start: String = Looks.current_id()
	Looks.set_look("reference")
	_check(Looks.is_reference(), "reference active")
	var c := Color(0.42, 0.61, 0.33)
	for s in Looks.SURFACES:
		_check(Looks.grade(s, c) == c, "reference grade of %s is the identity" % s)
	_check(Looks.floor_color("wood", c, Vector2i(3, 4)) == c, "reference floor colour untouched")
	var want := {"sun_base": 0.9, "shadow_mult": 1.0, "moon_energy": 0.55, "amb_energy_day": 0.62, "amb_energy_night": 0.62, "exposure_night": 1.1,
		"exposure_day": 1.0, "saturation": 1.0, "contrast": 1.0, "twilight_mix": 0.55, "lamp_energy": 1.0, "lamp_range": 1.0, "vignette": 0.0, "grain": 0.0, "wet_dark": 0.0, "window_glow": 0.0}
	for k in want:
		_check(is_equal_approx(Looks.ef(k, -9.0), float(want[k])), "reference env %s = %s" % [k, str(want[k])])
	var cols := {"night_sky": Color(0.035, 0.045, 0.11), "twilight": Color(0.92, 0.55, 0.42), "sun_warm": Color(1.0, 0.6, 0.36), "sun_white": Color(1.0, 0.97, 0.9),
		"moon_color": Color(0.55, 0.66, 1.0), "amb_day": Color(0.78, 0.8, 0.86), "amb_night": Color(0.2, 0.25, 0.46), "fog_tint": Color(0.72, 0.75, 0.78)}
	for k in cols:
		_check(Looks.ec(k).is_equal_approx(cols[k]), "reference env colour %s" % k)
	_check(UITheme.build() != null and UITheme.ACCENT == Color("#3fb8af") and UITheme.BG == Color("#1b2430"), "reference UI colours are today's")
	# a switch changes tints and floor wear, and switching back restores everything
	var sim_before := _sim_snapshot()
	var lis := [0]
	var cb := func(_i): lis[0] += 1
	Looks.bus.changed.connect(cb)
	Looks.set_look("grounded")
	_check(lis[0] == 1, "switching emits changed once")
	Looks.set_look("grounded")
	_check(lis[0] == 1, "switching to the same look is silent")
	_check(Looks.grade("grass", c) != c, "grounded changes grass")
	_check(Looks.floor_color("wood", c, Vector2i(3, 4)) != c, "grounded changes floors")
	_check(Looks.grade("grass", c).s < c.s, "grounded desaturates grass")
	_check(Looks.floor_color("wood", c, Vector2i(3, 4)) == Looks.floor_color("wood", c, Vector2i(3, 4)), "wear is deterministic (no rng)")
	_check(Looks.ef("amb_energy_night") < 0.5 and Looks.ef("window_glow") > 0.0, "grounded has dark nights and lit windows")
	UITheme.build()
	_check(UITheme.ACCENT != Color("#3fb8af"), "grounded UI accent is not the mint")
	var wall := load("res://assets/models/wall.glb") as PackedScene
	if wall != null:
		var inst := wall.instantiate()
		Looks.tint_tree(inst)
		var tinted := _overrides(inst)
		_check(tinted > 0, "grounded tints glb wall materials (%d overrides)" % tinted)
		inst.free()
	Looks.set_look("reference")
	_check(Looks.grade("grass", c) == c and Looks.floor_color("wood", c, Vector2i(3, 4)) == c, "switching back restores the reference tints")
	if wall != null:
		var inst2 := wall.instantiate()
		Looks.tint_tree(inst2)
		_check(_overrides(inst2) == 0, "reference leaves glb materials alone")
		inst2.free()
	UITheme.build()
	_check(UITheme.ACCENT == Color("#3fb8af"), "UI colours come back with the reference look")
	_check(_sim_snapshot() == sim_before, "a look switch touches no sim state")
	Looks.bus.changed.disconnect(cb)
	Looks.set_look(start)
	return fails


func _overrides(n: Node) -> int:
	var k := 0
	if n is MeshInstance3D:
		for s in (n as MeshInstance3D).mesh.get_surface_count():
			if (n as MeshInstance3D).get_surface_override_material(s) != null:
				k += 1
	for c in n.get_children():
		k += _overrides(c)
	return k


func _sim_snapshot() -> String:
	var root: Window = Engine.get_main_loop().root
	var W = root.get_node_or_null("World")
	var clk = root.get_node_or_null("Clock")
	var objs: int = W.all_objects().size() if W != null else -1
	var folk: int = W.all_folk().size() if W != null else -1
	return "%s|%s|%d|%d|%d" % [str(clk.total_minutes) if clk != null else "-", "-", objs, folk, W.floors.size() if W != null else -1]
