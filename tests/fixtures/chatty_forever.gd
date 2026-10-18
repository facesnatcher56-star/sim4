extends SceneTree
## Fixture: loops forever while printing (never silent), for the guard -MaxSeconds test. Quits itself after 120 s.
func _process(_d: float) -> bool:
	print("still going ", Time.get_ticks_msec())
	OS.delay_msec(100)
	if Time.get_ticks_msec() > 120000:
		quit(0)
	return false
