extends RefCounted
## Fixture for watchdog tests: a pure synchronous loop that never ends. Only run via run_all.gd --fixture=slow_forever_test.
func run() -> Array:
	while true:
		OS.delay_msec(50)
	return []
