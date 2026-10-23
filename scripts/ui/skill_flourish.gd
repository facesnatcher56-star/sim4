class_name SkillFlourish
extends Control
## Task 59: when the player's character gets better at a skill, a small quiet flourish over their head: a few sparks of the accent and one line
## ("Cooking improved"), rising and fading in about two seconds, with a sound cue. No level number or odds (quiet depth); the skill list has the rest.

const LIFE := 2.2
var lot_view = null
var _items: Array = []          # {folk_id, text, t}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	UIU.connect_ev("skill_changed", _on_skill)


func _on_skill(fid: int, skill: String, level: int) -> void:
	if fid != Pawn.of() or level <= 0:
		return
	var label := str((UIU.tbl("skills").get(skill, {}) as Dictionary).get("label", UIU.sentence(skill)))
	_items.append({"folk_id": fid, "text": "%s improved" % label, "t": 0.0})
	UISound.cue("skill_up")


func _process(delta: float) -> void:
	if _items.is_empty():
		return
	for it in _items:
		it["t"] = float(it["t"]) + delta
	_items = _items.filter(func(it): return float(it["t"]) < LIFE)
	queue_redraw()


func _draw() -> void:
	if lot_view == null or not lot_view.has_method("screen_pos"):
		return
	var font := get_theme_default_font()
	for it in _items:
		var p = lot_view.call("screen_pos", "folk", int(it["folk_id"]))
		if not (p is Vector2) or p.x < 0.0:
			continue
		var t: float = float(it["t"])
		var a := clampf((LIFE - t) / 0.7, 0.0, 1.0) * clampf(t / 0.15, 0.0, 1.0)
		var c: Vector2 = p - Vector2(0, 28.0 + t * 14.0)
		var acc := Color(UITheme.sem("coin"), a)
		for i in 6:          # a small ring of sparks that opens out
			var ang := TAU * float(i) / 6.0 + t
			var d := 10.0 + t * 16.0
			ProgressIcons.draw(self, "star", c + Vector2(cos(ang), sin(ang)) * d, 4.0, acc)
		var txt: String = str(it["text"])
		var w: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string_outline(font, c + Vector2(-w * 0.5, -14.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.6 * a))
		draw_string(font, c + Vector2(-w * 0.5, -14.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(UITheme.TEXT, a))
