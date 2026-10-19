extends RefCounted
## Shared helpers for vehicle_* tests (no run(), so the runner skips it): a real-map game, a headless VehicleView (no meshes), vehicle seconds driven by hand.

const Kit = preload("res://tests/hood_kit.gd")

static var _acc: float = 0.0


static func game(start: String = "small") -> Array:
	var folk: Array = Kit.new_game(start)
	StoryPacing.enabled = false
	CityState.reset()
	UtilityEvents.dice_on = false
	VehicleBays.forget()
	return folk


## A headless layer (draw = false) focused on `points` (world x, z). Added under the root so its signals work.
static func layer(points: Array) -> VehicleView:
	var vv := VehicleView.new()
	vv.draw = false
	vv.forced_focus = points
	Kit.root().add_child(vv)
	return vv


## Real seconds of play at a game speed: the layer is driven frame by frame and the game clock follows (1 game minute per second at speed 1), like the game does.
static func run_seconds(vv: VehicleView, seconds: float, speed: int = 1, dt: float = 0.05) -> void:
	var n: int = int(seconds / dt)
	for _i in n:
		_acc += dt * float(Clock.MIN_PER_SEC[clampi(speed, 0, 3)])
		var whole: int = int(_acc)
		if whole > 0:
			_acc -= float(whole)
			SimEnv.clock().advance_minutes(whole)
		vv.advance(dt, speed)


static func free_layer(vv: VehicleView) -> void:
	if vv != null and is_instance_valid(vv):
		vv.get_parent().remove_child(vv)
		vv.free()
