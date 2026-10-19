class_name CoopRate
extends RefCounted
## Token bucket for the packets one peer may send to the host (per second `rate`, burst `burst`). `now` is in seconds and is
## passed in, so tests can drive it without a clock.

var rate: float
var burst: float
var tokens: float
var last: float = -1.0
var dropped: int = 0

func _init(p_rate: float = 30.0, p_burst: float = 60.0) -> void:
	rate = p_rate
	burst = p_burst
	tokens = p_burst

func allow(now: float) -> bool:
	if last >= 0.0:
		tokens = minf(burst, tokens + (now - last) * rate)
	last = now
	if tokens < 1.0:
		dropped += 1
		return false
	tokens -= 1.0
	return true
