extends "res://tests/determinism_test.gd"
## Slow variant: 3 full game days from the same seed twice (see determinism_test.gd).

func _plan() -> Array:
	return [3 * 1440, 1, 7]
