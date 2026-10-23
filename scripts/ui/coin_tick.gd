class_name CoinTick
extends Label
## Task 59: when the household's money changes, a small "+20" or "-140" rises out of the coins in the top bar and fades (with a sound cue).
## Only the amount that just came in or went out, which the player already knows; never a balance forecast.

const LIFE := 1.6
var _anchor: Control
var _last := -1
var _t := 0.0


func _init(anchor: Control) -> void:
	_anchor = anchor
	top_level = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override("font_size", 14)
	visible = false


func _ready() -> void:
	UIU.connect_ev("coins_changed", _on_coins)


func _on_coins(hh: int, amount: int) -> void:
	if hh <= 0 or (CoopTime.active and hh != Players.primary_household()):
		return
	if _last < 0:
		_last = amount          # the first value is the starting balance, not a change
		return
	var d := amount - _last
	_last = amount
	if d == 0:
		return
	text = ("+%d" % d) if d > 0 else ("%d" % d)
	add_theme_color_override("font_color", UITheme.sem("good_text") if d > 0 else UITheme.sem("low_text"))
	_t = 0.0
	visible = true
	UISound.cue("coin_in" if d > 0 else "coin_out")


func _process(delta: float) -> void:
	if not visible or _anchor == null:
		return
	_t += delta
	if _t >= LIFE:
		visible = false
		return
	var r := _anchor.get_global_rect()
	reset_size()
	global_position = Vector2(r.position.x + (r.size.x - size.x) * 0.5, r.end.y + 2.0 - _t * 6.0)
	modulate.a = clampf((LIFE - _t) / 0.6, 0.0, 1.0)
