extends RefCounted
## WeatherView headless: attaches to a stand-in lot, follows Weather / Clock, never crashes without a renderer.

const W = preload("res://tests/weather_kit.gd")

class FakeLot:
	extends Node3D
	var _sun: DirectionalLight3D = DirectionalLight3D.new()
	var _env: Environment = Environment.new()
	var _target: Vector3 = Vector3(16, 0, 12)
	var _zoom: float = 14.0
	var _ground_mi: MeshInstance3D = null

func run() -> Array:
	var f: Array = []
	var w: StubWorld = W.setup(321)
	var lot := FakeLot.new()
	var wv := WeatherView.new()
	lot.add_child(wv)
	lot.add_child(lot._sun)
	wv.attach(lot)
	W.expect(f, wv.headless, "tests run headless")
	W.expect(f, wv.rain == null and wv.snow == null, "no particles are created headless")
	# noon vs midnight
	SimEnv.clock().total_minutes = W.at(11, 12)
	Weather.force("sunny")
	wv._apply(100.0, true)
	var noon_energy: float = lot._sun.light_energy
	var noon_bg: Color = lot._env.background_color
	SimEnv.clock().total_minutes = W.at(11, 1)
	wv._apply(100.0, true)
	W.expect(f, lot._sun.light_energy < noon_energy * 0.2, "the sun is down at 1am (%f vs %f)" % [lot._sun.light_energy, noon_energy])
	W.expect(f, lot._env.background_color.get_luminance() < noon_bg.get_luminance() * 0.5, "the sky is dark at night")
	W.expect(f, lot._env.ambient_light_energy > 0.4, "ambient stays readable at night (%f)" % lot._env.ambient_light_energy)
	for v in [lot._sun.light_energy, lot._env.ambient_light_energy, lot._env.background_color.r]:
		W.expect(f, not is_nan(v) and not is_inf(v), "no NaN in the rig")
	# sun moves across the sky
	var yaws: Array = []
	for h in [7.0, 10.0, 13.0, 16.0, 18.0]:
		SimEnv.clock().total_minutes = W.at(11, int(h))
		wv._apply(100.0, true)
		yaws.append(lot._sun.rotation.y)
	W.expect(f, yaws[0] < yaws[2] and yaws[2] < yaws[4], "sun azimuth sweeps through the day: %s" % str(yaws))
	# weather parameters follow
	SimEnv.clock().total_minutes = W.at(11, 12)
	Weather.force("rain")
	wv._apply(100.0, true)
	W.expect(f, float(wv.p["rain"]) > 0.5 and float(wv.p["snow"]) < 0.01, "rain parameter follows the weather")
	W.expect(f, lot._sun.light_energy < noon_energy * 0.7, "rain dims the sun")
	Weather.force("fog")
	wv._apply(100.0, true)
	W.expect(f, lot._env.fog_enabled, "fog weather enables fog")
	Weather.force("snow", 0.8)
	wv._apply(100.0, true)
	W.expect(f, float(wv.p["snow"]) > 0.4 and float(wv.p["snowcover"]) > 0.7, "snow parameters")
	Weather.force("sunny", 0.0)
	wv._apply(100.0, true)
	W.expect(f, not lot._env.fog_enabled, "clear weather disables fog")
	# smooth transitions: one second of frames does not jump all the way
	Weather.force("thunderstorm")
	wv._apply(100.0, true)
	Weather.force("sunny")
	wv._apply(0.05, false)
	W.expect(f, float(wv.p["light"]) < 0.8, "light eases toward the new weather instead of snapping (%f)" % float(wv.p["light"]))
	# lightning flash
	wv._flash = 0.0
	wv._apply(0.0, false)
	var before: float = lot._sun.light_energy
	wv._flash = 1.0
	wv._apply(0.0, false)
	wv._apply(0.0, false)
	W.expect(f, lot._sun.light_energy > before, "a lightning flash brightens the scene")
	# two years of hours without trouble
	Weather.unforce()
	for h2 in range(0, 24 * 56, 3):
		SimEnv.clock().total_minutes = h2 * 60
		wv._apply(1.0, false)
	W.expect(f, not is_nan(lot._sun.light_energy), "two years of daylight maths are finite")
	lot.free()
	W.teardown()
	return f
