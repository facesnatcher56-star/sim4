class_name RainRoofs
extends Node3D
## Rain and snow stop at the roof of every single-storey building too (LevelView only covers multi-floor buildings): a particle collision
## box over each group of indoor ground-floor tiles (the precipitation uses COLLISION_HIDE_ON_CONTACT). Godot uses at most 32 colliders
## per particle system, so only the boxes nearest the camera are switched on. Rebuilt a moment after walls change.

const HEIGHT := 100.0        # the whole column: with the roof cut away, drops falling above it would be drawn over the room
const ACTIVE := 24           # leave room for LevelView's blockers of tall buildings
var _dirty := true
var _wait := 0.0
var _near_clock := 0.0


static func ensure_on(parent: Node3D) -> RainRoofs:
	var rr := RainRoofs.new()
	rr.name = "RainRoofs"
	parent.add_child(rr)
	return rr


func _ready() -> void:
	World.walls_changed.connect(_mark)
	World.world_reset.connect(_mark)


func _mark() -> void:
	_dirty = true
	_wait = 0.5          # building a wall emits many changes: rebuild once they settle


func _process(delta: float) -> void:
	if _dirty:
		_wait -= delta
		if _wait <= 0.0:
			_dirty = false
			_rebuild()
	_near_clock -= delta
	if _near_clock <= 0.0:
		_near_clock = 0.5
		_switch_nearest()


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	for rc in indoor_rects():
		var box := GPUParticlesCollisionBox3D.new()
		box.size = Vector3(rc.size.x, HEIGHT, rc.size.y)
		box.position = Vector3(rc.position.x + rc.size.x * 0.5, HEIGHT * 0.5, rc.position.y + rc.size.y * 0.5)
		add_child(box)
	_near_clock = 0.0


func _switch_nearest() -> void:
	var lot = get_parent().get("lot")
	var t = lot.get("_target") if lot != null else null
	if not (t is Vector3):
		return
	var boxes: Array = get_children().filter(func(c): return not c.is_queued_for_deletion())
	boxes.sort_custom(func(a, b): return _flat(a.position, t) < _flat(b.position, t))
	for i in boxes.size():
		boxes[i].visible = i < ACTIVE


static func _flat(p: Vector3, t: Vector3) -> float:
	return Vector2(p.x - t.x, p.z - t.z).length_squared()


## One rectangle per group of touching indoor ground tiles (a building's rooms): its bounding box.
static func indoor_rects() -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	var seen: Dictionary = {}
	for y in World.height:
		for x in World.width:
			var start := Vector2i(x, y)
			if seen.has(start) or not _indoor(start):
				continue
			var rc := Rect2i(start, Vector2i.ONE)
			var stack: Array[Vector2i] = [start]
			seen[start] = true
			while not stack.is_empty():
				var c: Vector2i = stack.pop_back()
				rc = rc.expand(c).expand(c + Vector2i.ONE)
				for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var n: Vector2i = c + d
					if not seen.has(n) and _indoor(n):
						seen[n] = true
						stack.append(n)
			out.append(rc)
	return out


## The camera target (world position) is over an indoor ground tile.
static func indoor_at(p: Vector3) -> bool:
	return _indoor(Vector2i(floori(p.x), floori(p.z)))


static func _indoor(t: Vector2i) -> bool:
	return World.in_bounds(t) and World.get_floor(t) != "" and not World.rooms.is_outdoor(t, 0)
