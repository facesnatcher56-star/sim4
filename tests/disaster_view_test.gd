extends RefCounted
## DisasterView (headless: parameter maths only): siren pulse during the warning, blackout during an outage, whiteout in a blizzard,
## flood water for a flooded home, haze for a wildfire, quake shake timer, funnel after the impact, and cleanup of its signal.

const K = preload("res://tests/systems_kit.gd")
const D = preload("res://tests/disaster_kit.gd")

func run() -> Array:
	var f: Array = []
	var w := D.setup()
	D.home(w)
	var holder := Node3D.new()
	var dv: DisasterView = DisasterView.ensure_on(holder)
	K.expect(f, DisasterView.ensure_on(holder) == dv, "ensure_on is idempotent")
	for i in 20:
		dv._process(0.1)
	K.expect(f, float(dv.p["siren"]) < 0.01 and float(dv.p["dark"]) < 0.01 and float(dv.p["white"]) < 0.01, "calm: no effects")
	DisasterState.siren_when_forced = true
	D.force_home("tornado", 1)
	var peak: float = 0.0
	for i in 30:
		dv._process(0.1)
		peak = maxf(peak, float(dv.p["siren"]))
	K.expect(f, peak > 0.1, "the siren pulses during the warning (peak %.2f)" % peak)
	D.run_minutes(8)
	for i in 5:
		dv._process(0.1)
	K.expect(f, float(dv.p["funnel"]) > 0.5, "funnel shows after the impact")
	D.force_home("power_outage")
	for i in 30:
		dv._process(0.1)
	K.expect(f, float(dv.p["dark"]) > 0.1, "blackout dims the view")
	D.force_home("flood", 0)
	Weather.force("snow")
	D.force_home("blizzard", 0)
	D.force_home("wildfire", 0)
	for i in 40:
		dv._process(0.1)
	K.expect(f, float(dv.p["white"]) > 0.1 and float(dv.p["haze"]) > 0.05 and float(dv.p["flood"]) > 0.3, "whiteout, haze and water follow the running events")
	D.force_home("earthquake", 0)
	K.expect(f, dv.shake_left > 1.0, "the quake shakes the camera")
	D.force_home("hailstorm", 0)
	K.expect(f, dv.hail_left > 1.0, "hail burst")
	holder.free()
	Weather.unforce()
	K.teardown()
	return f
