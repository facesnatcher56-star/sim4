class_name LookKits
extends RefCounted
## Per-object recolouring of furniture and vehicle glbs (task 41 part C). View only: no sim state, no rng (a hash of the object / vehicle id).
## data/looks.json: `kit_class` maps glb material names to kit classes (wood, fabric, metal, enamel, paint, brass, book, carpaint, service_paint); each look has
## `kits.<class>` = {sat, val, tint} (the look's base palette) + wear effects {fade, dark, dirt, dirt_mix, rust, rust_mix} applied by the object's AGE.
## Age (0 new .. 1 ancient) = hash of the id, pushed up for cheap objects and down for expensive ones (`kit_age.tiers`, by catalogue price = the wealth tier of
## the object). Three buckets (nice / used / worn) keep the number of distinct meshes small; cars also pick a dirt or a rust variant by the hash.
## The tint goes into a cached DUPLICATE of the glb mesh (surface materials replaced, resource names kept), so ObjectVisualNodes' state overrides still work on top.
## Reference look: does nothing.

static var _mesh_cache: Dictionary = {}       # "<mesh id>|<look>|<bucket>|<variant>" -> mesh (or null if nothing to tint)
static var _mat_cache: Dictionary = {}

const FACTORS := [0.0, 0.5, 1.0]              # nice, used, worn


static func clear_cache() -> void:
	_mesh_cache.clear()
	_mat_cache.clear()


static func _hash01(a: int, b: int) -> float:
	var h: int = (a * 73856093) ^ (b * 19349663) ^ 0x2545F491
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0


## Age 0..1 of an object: its id hash, pushed by the wealth tier of its price (cheap things are older / more worn).
static func age(id: int, def_id: String, price: float, bias: float = 0.0) -> float:
	var b := bias
	for t in (Looks.data().get("kit_age", {}) as Dictionary).get("tiers", []):
		if price <= float(t["max_price"]):
			b += float(t["bias"])
			break
	return clampf(_hash01(id, def_id.hash() & 0xFFFF) * 0.8 + b, 0.0, 1.0)


## 0 nice, 1 used, 2 worn.
static func bucket(a: float) -> int:
	var th: Array = (Looks.data().get("kit_age", {}) as Dictionary).get("buckets", [0.33, 0.66])
	return 0 if a < float(th[0]) else (1 if a < float(th[1]) else 2)


## "dirt" or "rust": the weathering a car shows when worn.
static func variant_of(id: int) -> String:
	return "rust" if _hash01(id, 77) < 0.5 else "dirt"


static func class_of(mname: String) -> String:
	return str((Looks.data().get("kit_class", {}) as Dictionary).get(mname, ""))


## Colour of a material of kit class `cls` at wear bucket `bk` (0..2) and weathering `variant`. Pure: used by tests too.
static func colour(cls: String, c: Color, bk: int, variant: String) -> Color:
	var k: Dictionary = (Looks.cur().get("kits", {}) as Dictionary).get(cls, {})
	if k.is_empty():
		return c
	var f: float = FACTORS[clampi(bk, 0, 2)]
	var s := clampf(c.s * float(k.get("sat", 1.0)), 0.0, 1.0)
	var v := clampf(c.v * float(k.get("val", 1.0)), 0.0, 1.0)
	s *= 1.0 - float(k.get("fade", 0.0)) * f
	v *= 1.0 - float(k.get("dark", 0.0)) * f
	var t := Color(str(k.get("tint", "#ffffff")))
	var o := Color.from_hsv(c.h, s, v, c.a)
	o = Color(o.r * t.r, o.g * t.g, o.b * t.b, c.a)
	if variant == "rust" and k.has("rust"):
		o = o.lerp(Color(str(k["rust"])), float(k.get("rust_mix", 0.0)) * f)
	elif k.has("dirt"):
		o = o.lerp(Color(str(k["dirt"])), float(k.get("dirt_mix", 0.0)) * f)
	return Color(o.r, o.g, o.b, c.a)


## Recolour an instantiated furniture / vehicle model for object `id` of kit `def_id`. Idempotent per node.
static func apply(root: Node, id: int, def_id: String, price: float, bias: float = 0.0) -> void:
	if Looks.is_reference() or root == null or root.has_meta("kitted"):
		return
	root.set_meta("kitted", Looks.current_id())
	var bk := bucket(age(id, def_id, price, bias))
	_walk(root, bk, variant_of(id))


static func _walk(n: Node, bk: int, variant: String) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi := n as MeshInstance3D
		var m2 := _tinted_mesh(mi.mesh, bk, variant)
		if m2 != null:
			mi.mesh = m2
	for c in n.get_children():
		_walk(c, bk, variant)


static func _tinted_mesh(mesh: Mesh, bk: int, variant: String) -> Mesh:
	var key := "%d|%s|%d|%s" % [mesh.get_instance_id(), Looks.current_id(), bk, variant]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var out: Mesh = null
	var any := false
	for s in mesh.get_surface_count():
		var src := mesh.surface_get_material(s) as BaseMaterial3D
		if src != null and class_of(src.resource_name) != "":
			any = true
			break
	if any:
		out = mesh.duplicate()
		for s in out.get_surface_count():
			var src := out.surface_get_material(s) as BaseMaterial3D
			if src == null:
				continue
			var cls := class_of(src.resource_name)
			if cls == "":
				continue
			var mk := "%d|%s|%d|%s" % [src.get_instance_id(), Looks.current_id(), bk, variant]
			var m: BaseMaterial3D = _mat_cache.get(mk)
			if m == null:
				m = src.duplicate() as BaseMaterial3D
				m.resource_name = src.resource_name
				m.albedo_color = colour(cls, src.albedo_color, bk, variant)
				var f: float = FACTORS[bk]
				m.roughness = lerpf(m.roughness, 1.0, f * 0.45)               # scuffed, dull
				if cls == "metal" or cls == "brass":
					m.metallic = m.metallic * (1.0 - 0.4 * f)
				_mat_cache[mk] = m
			out.surface_set_material(s, m)
	_mesh_cache[key] = out
	return out
