class_name LightMood
extends RefCounted
## Lighting and weather mood maths (task 41 part C). Pure static functions, view only: no sim state, no rng, no nodes.
## WeatherView / weather_lamps call these; tests/light_mood_test.gd checks them without a window.
##  * night readability floor ("Night brightness" setting): the ambient never drops below it, a faint fill follows the selected folk
##  * which windows are lit at which hour (occupancy curve), dusk vs dawn colour, seasonal grey, wet-street mood, puddle tiles, fixture lights

## Lowest ambient energy at full night for the Night brightness setting 0..1 (0 = true dark, 1 = bright moonlit).
static func floor_energy(nb: float) -> float:
	return lerpf(0.06, 0.40, clampf(nb, 0.0, 1.0))


const NB_DEFAULT := 0.35        # the setting's default: the look's own night, untouched

## How the setting scales the look's own night ambient: below the default it gets darker (down to 0.35x), above it the floor takes over.
static func night_scale(nb: float) -> float:
	return 1.0 if nb >= NB_DEFAULT else lerpf(0.35, 1.0, clampf(nb, 0.0, 1.0) / NB_DEFAULT)


## Ambient colour: the look's night blue, drifting to a lighter neutral moonlit grey as Night brightness goes above its default (so the floor shows colour, not just grey).
static func ambient_color(night_c: Color, day_c: Color, dl: float, nb: float) -> Color:
	var lift := clampf((nb - NB_DEFAULT) / (1.0 - NB_DEFAULT), 0.0, 1.0) * 0.8
	return night_c.lerp(Color(0.45, 0.5, 0.68), lift).lerp(day_c, clampf(dl, 0.0, 1.0))


## Ambient light energy: the look's own day / night blend, dimmed by overcast, but never below the readability floor at night.
static func ambient_energy(night_e: float, day_e: float, dl: float, dim: float, nb: float) -> float:
	var base := lerpf(night_e * night_scale(nb), day_e, clampf(dl, 0.0, 1.0)) * dim
	return maxf(base, floor_energy(nb) * (1.0 - clampf(dl, 0.0, 1.0)))


## Faint neutral fill on the selected folk / home in the dark (OmniLight energy). 0 by day.
static func fill_energy(dark: float, nb: float) -> float:
	return clampf(dark, 0.0, 1.0) * lerpf(0.25, 0.85, clampf(nb, 0.0, 1.0))


## Share of windows that have a light on at this hour: evening busy, small hours quiet, morning stirring.
static func occupancy(hour: float) -> float:
	var h := fposmod(hour, 24.0)
	var pts := [[0.0, 0.25], [2.0, 0.1], [4.0, 0.08], [6.0, 0.4], [7.5, 0.55], [9.0, 0.2], [16.0, 0.2], [18.0, 0.7], [21.0, 0.95], [23.0, 0.55], [24.0, 0.25]]
	for i in range(pts.size() - 1):
		var a: Array = pts[i]
		var b: Array = pts[i + 1]
		if h >= float(a[0]) and h <= float(b[0]):
			var f := (h - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001)
			return lerpf(float(a[1]), float(b[1]), f)
	return 0.25


## Window glow factor 0..1 of a window with personal threshold `lit` (0..1, per building): lit while the hour's occupancy exceeds it, soft edge.
static func window_lit(lit: float, hour: float) -> float:
	return smoothstep(lit - 0.08, lit + 0.08, occupancy(hour))


## Twilight colour: warm orange at dusk, a cooler pink-grey at dawn.
static func twilight_color(hour: float, dusk: Color, dawn: Color) -> Color:
	return dawn if fposmod(hour, 24.0) < 12.0 else dusk


## Value over the four seasons (spring, summer, autumn, winter) at season position `pos` (0.5 = mid spring ... as Seasons.year_pos), smooth.
static func season_value(arr: Array, pos: float) -> float:
	if arr.size() < 4:
		return 1.0
	var q := fposmod(pos - 0.5, 4.0)
	var i0 := int(floorf(q)) % 4
	var f := q - floorf(q)
	f = f * f * (3.0 - 2.0 * f)
	return lerpf(float(arr[i0]), float(arr[(i0 + 1) % 4]), f)


## Wet-street mood for a wetness 0..1: how dark the film is, how glossy, how much the ambient dims.
static func wet_mood(wet: float, wet_dark: float) -> Dictionary:
	var w := clampf(wet, 0.0, 1.0)
	return {"dark": w * wet_dark, "rough": lerpf(0.8, 0.12, w), "dim": lerpf(1.0, 0.92, w)}


## A tile that holds a puddle while it is wet: about one road tile in five, in small clusters. Deterministic.
static func puddle(t: Vector2i) -> bool:
	var cx := t.x >> 1
	var cy := t.y >> 1
	var h: int = (cx * 73856093) ^ (cy * 19349663) ^ 0x51ed
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0 < 0.2 and ((t.x + t.y) & 3) != 3


## Alpha of the wet film on a tile: puddles are the darkest.
static func wet_tile_alpha(t: Vector2i) -> float:
	return 1.0 if puddle(t) else 0.6


# ------------------------------------------------------------------ fixture lights (data/looks.json "lights")

static var _lights: Dictionary = {}


static func light_defs() -> Dictionary:
	if _lights.is_empty():
		var d: Dictionary = Looks.data().get("lights", {})
		for k in d:
			var e: Dictionary = (d[k] as Dictionary).duplicate()
			e["color"] = Color(str(e.get("color", "#ffd199")))
			_lights[k] = e
	return _lights


## Colour temperature words used by the data: warm (lamps, bulbs), fire, cold (screens, vending machines).
static func is_cold(def: Dictionary) -> bool:
	var c: Color = def.get("color", Color.WHITE)
	return c.b > c.r
