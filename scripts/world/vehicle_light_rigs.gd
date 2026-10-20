class_name VehicleLightRigs
extends RefCounted
## Real lights of the vehicles (task 42, display only), given to the nearest few so the frame budget holds (data/vehicles.json "lights"): a SpotLight3D low beam (soft cone, about 20 m, tilted
## a little to the road) for the nearest `real_n` vehicles whose headlights are on, an OmniLight3D flashing blue and red for the nearest `emergency_n` emergency vehicles. Everything else
## has the emissive lamps, the beam decal and the flash discs of VehicleLights. Cause: a headlight lights the road and what stands on it; a siren lights the street it drives through.
##   rigs.assign(nodes: Dictionary, cam: Vector2, ctx)      rigs.tick(flash_on)      rigs.count() -> {spots, omnis}      rigs.clear()

var _spots: Dictionary = {}          # vehicle id -> SpotLight3D
var _omnis: Dictionary = {}          # vehicle id -> OmniLight3D


static func cfg() -> Dictionary:
	return SysUtil.table("vehicles").get("lights", {})


func count() -> Dictionary:
	return {"spots": _spots.size(), "omnis": _omnis.size()}


func clear() -> void:
	for id in _spots:
		if is_instance_valid(_spots[id]):
			(_spots[id] as Node).queue_free()
	for id2 in _omnis:
		if is_instance_valid(_omnis[id2]):
			(_omnis[id2] as Node).queue_free()
	_spots.clear()
	_omnis.clear()


func assign(nodes: Dictionary, cam: Vector2, ctx: Dictionary) -> void:
	var c: Dictionary = cfg()
	var heads: Array = []
	var sirens: Array = []
	for id in nodes:
		var rec: Dictionary = nodes[id]
		var root: Node3D = rec["root"]
		if not is_instance_valid(root) or not root.visible:
			continue
		var d: float = Vector2(root.position.x, root.position.z).distance_to(cam)
		if bool(rec.get("head", false)):
			heads.append([d, id])
		if bool(rec.get("siren", false)):
			sirens.append([d, id])
	heads.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	sirens.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var keep_s: Dictionary = {}
	for k in mini(heads.size(), int(c.get("real_n", 6))):
		if float((heads[k] as Array)[0]) <= float(c.get("real_radius", 48.0)):
			keep_s[(heads[k] as Array)[1]] = true
	var keep_o: Dictionary = {}
	for k2 in mini(sirens.size(), int(c.get("emergency_n", 3))):
		keep_o[(sirens[k2] as Array)[1]] = true
	for id2 in _spots.keys():
		if not keep_s.has(id2) or not nodes.has(id2):
			if is_instance_valid(_spots[id2]):
				(_spots[id2] as Node).queue_free()
			_spots.erase(id2)
	for id3 in _omnis.keys():
		if not keep_o.has(id3) or not nodes.has(id3):
			if is_instance_valid(_omnis[id3]):
				(_omnis[id3] as Node).queue_free()
			_omnis.erase(id3)
	for id4 in keep_s:
		if not _spots.has(id4):
			_spots[id4] = _make_spot(nodes[id4], c)
		(_spots[id4] as SpotLight3D).light_energy = float(c.get("spot_energy", 5.0)) * float(ctx["dark"])
	for id5 in keep_o:
		if not _omnis.has(id5):
			_omnis[id5] = _make_omni(nodes[id5], c)


func _make_spot(rec: Dictionary, c: Dictionary) -> SpotLight3D:
	var s := SpotLight3D.new()
	s.name = "LowBeam"
	s.spot_range = float(c.get("spot_range", 20.0))
	s.spot_angle = float(c.get("spot_angle", 26.0))
	s.spot_attenuation = float(c.get("spot_attenuation", 1.0))
	s.light_color = Color(1.0, 0.93, 0.78)
	s.shadow_enabled = false
	s.rotation.x = deg_to_rad(-float(c.get("spot_pitch", 9.0)))
	s.position = Vector3(0.0, 0.75, -float(rec.get("half_len", 2.1)) - 0.1)
	(rec["root"] as Node3D).add_child(s)
	return s


func _make_omni(rec: Dictionary, c: Dictionary) -> OmniLight3D:
	var o := OmniLight3D.new()
	o.name = "Flasher"
	o.omni_range = float(c.get("flash_range", 11.0))
	o.omni_attenuation = 1.2
	o.light_energy = float(c.get("flash_energy", 3.0))
	o.shadow_enabled = false
	o.position = Vector3(0.0, 2.4, 0.0)
	(rec["root"] as Node3D).add_child(o)
	return o


## Blue and red take turns (every frame: a handful of lights).
func tick(flash_on: bool) -> void:
	for id in _omnis:
		if is_instance_valid(_omnis[id]):
			(_omnis[id] as OmniLight3D).light_color = Color(1.0, 0.12, 0.08) if flash_on else Color(0.12, 0.3, 1.0)
