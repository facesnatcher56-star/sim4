extends SceneTree
## Prints the scheduler registry as a markdown table (paste into docs/PERFORMANCE.md "Scheduler registry"):
##   powershell -File tools/godot_guard.ps1 -Seconds 120 -Args "--headless","--path",".","--script","res://tools/sched_describe.gd"
func _process(_d: float) -> bool:
	var clk = load("res://scripts/core/clock.gd").new()
	var s := SimScheduler.of(clk)
	var sm := SystemsManager.new()
	SimRegistry.install_director(s, root.get_node("SimDirector"))
	SimRegistry.install_systems(s, sm)
	SimRegistry.install_social(s)
	SimRegistry.install_scenario(s)
	SimRegistry.install_app(s, sm)
	print("REGISTRY_BEGIN")
	print(s.describe())
	print("REGISTRY_END")
	quit(0)
	return true
