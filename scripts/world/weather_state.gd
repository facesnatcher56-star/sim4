extends Node3D
## Shared constants / state for WeatherView (chain: weather_state > weather_scenery > weather_precip > weather_lamps > weather_view).
## Renders the sky / sun / moon / weather for a LotView (added as its child by LotView._ready; see attach()):
##  * day-night cycle: sun direction + colour, moon + cool ambient at night, sky colour, twilight, overcast dimming
##  * fog (depth fog on the orthographic camera), rain / snow GPUParticles3D that follow the camera, lightning flashes
##  * seasonal ground tint (grass overlay), snow cover + wet look, bare / leafy / blossom trees scenery ring
##  * warm point lights at lamps / fireplaces when it is dark
## Everything is driven from Weather / Seasons / Clock every frame (smoothed), so it follows time warp and forced weather.
## Headless: only the cheap parameter maths run (no particles, lights or scenery) so tests cannot crash.

signal thunder(strength: float)

const TREE_COUNT := 46
const LIGHT_DEFS := {"lamp": {"y": 1.5, "color": Color(1.0, 0.82, 0.55), "range": 5.5, "energy": 1.6},
	"pendant_light": {"y": 2.2, "color": Color(1.0, 0.85, 0.6), "range": 5.0, "energy": 1.5},
	"fireplace": {"y": 0.7, "color": Color(1.0, 0.55, 0.25), "range": 5.5, "energy": 1.8, "state": "lit"},
	"nightstand": {"y": 1.0, "color": Color(1.0, 0.82, 0.55), "range": 3.5, "energy": 0.8}}
const MAX_LIGHTS := 18

var lot: Node3D = null
var sun: DirectionalLight3D = null
var env: Environment = null
var moon: DirectionalLight3D = null
var rain: GPUParticles3D = null
var snow: GPUParticles3D = null
var scenery: Node3D = null
var headless: bool = false
## Smoothed parameters (read by tests / screenshots).
var p: Dictionary = {"light": 1.0, "cloud": 0.0, "fog": 0.0, "rain": 0.0, "snow": 0.0, "wet": 0.0, "snowcover": 0.0, "daylight": 1.0}

var _grass_mat: StandardMaterial3D = null
var _snow_mat: StandardMaterial3D = null
var _leaf_mat: StandardMaterial3D = null
var _pine_mat: StandardMaterial3D = null
var _tree_dims: Vector2i = Vector2i.ZERO
var _trees: Array = []          # {root, canopy, pine, snow_cap}
var _flash: float = 0.0
var _flash_timer: float = 6.0
var _lamp_lights: Dictionary = {}   # object id -> OmniLight3D
var _lamp_timer: float = 0.0
var _sky_flash_col: Color = Color.WHITE
var time_scale_real: float = 1.0
var fixed_hour: float = -1.0        # >= 0 pins the sun to this hour (screenshots)


func _overlay_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 1.0
	m.albedo_color = Color(1, 1, 1, 0)
	return m


func _season_col(key: String, pos: float, default: Color) -> Color:
	var arr: Array = Seasons.cfg().get("seasons", [])
	if arr.size() < 4:
		return default
	var q: float = fposmod(pos - 0.5, 4.0)
	var i0: int = int(floor(q)) % 4
	var f: float = q - floor(q)
	f = f * f * (3.0 - 2.0 * f)
	var a := Color(str((arr[i0] as Dictionary).get(key, default.to_html())))
	var b := Color(str((arr[(i0 + 1) % 4] as Dictionary).get(key, default.to_html())))
	return a.lerp(b, f)


func _season_num(key: String, pos: float, default: float) -> float:
	var arr: Array = Seasons.cfg().get("seasons", [])
	if arr.size() < 4:
		return default
	var q: float = fposmod(pos - 0.5, 4.0)
	var i0: int = int(floor(q)) % 4
	var f: float = q - floor(q)
	f = f * f * (3.0 - 2.0 * f)
	return lerpf(float((arr[i0] as Dictionary).get(key, default)), float((arr[(i0 + 1) % 4] as Dictionary).get(key, default)), f)


func _smooth(cur: float, target: float, delta: float, rate: float) -> float:
	return lerpf(cur, target, clampf(1.0 - exp(-delta * rate), 0.0, 1.0))
