extends SceneTree
## Fixture: harmless long-running headless Godot (for the sweep test). Quits itself after 180 s as a safety net.
func _process(_d: float) -> bool:
	if Time.get_ticks_msec() > 180000:
		quit(0)
	OS.delay_msec(100)
	return false
