extends RefCounted
## Task 41 part C (fast): UI tone. No custom-drawn / hard-coded bright Color literal remains in scripts/ui outside an allowlist (they route through the
## look-aware UITheme: ACCENT / PANEL ..., sem("good") ..., tone(c)); the grounded palette has readable contrast and no mint accent; colour-blind cues stay.

var fails: Array = []

## Files that legitimately paint with their own colours (illustrations and swatches, not UI chrome).
const ALLOW := {
	"ui_theme.gd": "the theme itself and the semantic defaults",
	"uiu.gd": "mood / need palettes (colour-blind sets are fixed; the default ones go through UITheme.tone)",
	"face_icon.gd": "draws a folk's face from its own skin / hair colours",
	"house_thumb.gd": "illustration of a house",
	"lot_thumb.gd": "illustration of a lot",
	"folk_look_tabs.gd": "colour swatches the player picks from",
	"progress_icons.gd": "glyph interiors of the progress ring icons",
	"folk_preview.gd": "3D preview lighting, not UI colour",
}
const NEUTRAL_CHROMA := 0.12      # r,g,b literals whose max - min stays under this are neutral (greys, black / white veils)
const TEXT_KEYS := ["good", "good_text", "info", "warn", "bad", "coin", "coin_hi", "romance", "trust", "group", "low_text", "error", "caution", "friendly", "funny", "deep", "mean"]


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func run() -> Array:
	fails = []
	var start: String = Looks.current_id()
	_sweep()
	_palettes()
	Looks.set_look(start)
	UITheme.build()
	return fails


# ------------------------------------------------------------------ literal sweep
func _sweep() -> void:
	var hex := RegEx.create_from_string("Color\\(\\s*\"(#[0-9a-fA-F]{6,8})\"")
	var nums := RegEx.create_from_string("Color\\(\\s*([0-9.]+)\\s*,\\s*([0-9.]+)\\s*,\\s*([0-9.]+)")
	var named := RegEx.create_from_string("Color\\.(RED|GREEN|BLUE|YELLOW|ORANGE|CYAN|MAGENTA|PURPLE|PINK|LIME_GREEN|GOLD|AQUA)\\b")
	var d := DirAccess.open("res://scripts/ui")
	_check(d != null, "scripts/ui readable")
	if d == null:
		return
	var checked := 0
	for f in d.get_files():
		if not f.ends_with(".gd") or ALLOW.has(f):
			continue
		checked += 1
		var lines := FileAccess.get_file_as_string("res://scripts/ui/" + f).split("\n")
		for i in lines.size():
			var ln: String = lines[i]
			var code := ln.split("##")[0]
			if code.strip_edges().begins_with("#"):
				continue
			var tone_wrapped := code.find("UITheme.tone(") >= 0
			for m in hex.search_all(code):
				var c := Color(m.get_string(1))
				if _chroma(c) >= NEUTRAL_CHROMA and not tone_wrapped:
					fails.append("%s:%d hard-coded colour %s: use UITheme.sem()/ACCENT/tone()" % [f, i + 1, m.get_string(1)])
			for m in nums.search_all(code):
				var c2 := Color(float(m.get_string(1)), float(m.get_string(2)), float(m.get_string(3)))
				if _chroma(c2) >= NEUTRAL_CHROMA and not tone_wrapped:
					fails.append("%s:%d hard-coded colour (%s, %s, %s): use UITheme.sem()/ACCENT/tone()" % [f, i + 1, m.get_string(1), m.get_string(2), m.get_string(3)])
			if named.search(code) != null:
				fails.append("%s:%d named bright colour: use UITheme.sem()" % [f, i + 1])
	_check(checked > 40, "the sweep covered the UI files (%d)" % checked)


func _chroma(c: Color) -> float:
	return maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))


# ------------------------------------------------------------------ palettes
func _palettes() -> void:
	for id in Looks.ids():
		var sem: Dictionary = Looks.look(id).get("ui", {}).get("sem", {})
		for k in UITheme.SEM_DEFAULT:
			_check(sem.has(k), "%s ui.sem has %s" % [id, k])
	# reference keeps today's colours
	Looks.set_look("reference")
	UITheme.build()
	_check(UITheme.sem("good") == Color("#4cc78a") and UITheme.sem("bad") == Color("#e5534b") and UITheme.ACCENT == Color("#3fb8af"), "reference semantic colours are today's")
	_check(UITheme.tone(Color("#e5534b")) == Color("#e5534b"), "reference tone() is the identity")
	_check(UITheme.contrast(UITheme.TEXT, UITheme.PANEL) >= 7.0, "reference text contrast on panels")
	# grounded: sober
	Looks.set_look("grounded")
	UITheme.build()
	var bg: Color = Color(UITheme.PANEL)
	_check(UITheme.contrast(UITheme.TEXT, bg) >= 7.0, "grounded body text >= 7:1 on panels (%.1f)" % UITheme.contrast(UITheme.TEXT, bg))
	_check(UITheme.contrast(UITheme.MUTED, bg) >= 4.5, "grounded muted text >= 4.5:1 (%.1f)" % UITheme.contrast(UITheme.MUTED, bg))
	_check(UITheme.contrast(UITheme.ACCENT, bg) >= 3.0, "grounded accent >= 3:1 as a UI edge (%.1f)" % UITheme.contrast(UITheme.ACCENT, bg))
	for k in TEXT_KEYS:
		var r := UITheme.contrast(UITheme.sem(k), bg)
		_check(r >= 4.5, "grounded %s text >= 4.5:1 on panels (%.2f)" % [k, r])
		_check(UITheme.contrast(UITheme.sem(k), UITheme.BG) >= 4.5, "grounded %s >= 4.5:1 on the window background" % k)
	_check(UITheme.contrast(UITheme.sem("bubble_text"), UITheme.sem("bubble")) >= 7.0, "thought balloon text >= 7:1")
	# no loud mint / teal: accent is a muted brass, semantic colours are not saturated
	_check(UITheme.ACCENT.s < 0.45, "grounded accent is muted (s=%.2f)" % UITheme.ACCENT.s)
	var h := UITheme.ACCENT.h * 360.0
	_check(not (h > 150.0 and h < 200.0 and UITheme.ACCENT.s > 0.3), "grounded accent is not mint / teal")
	for k in UITheme.SEM_DEFAULT:
		_check(UITheme.sem(k).s < 0.62, "grounded %s is not a loud colour (s=%.2f)" % [k, UITheme.sem(k).s])
	# colour-blind safety: good / bad / warn keep distinct lightness AND text cues remain ("!" on warn/bad toasts, numbers on bars)
	_check(absf(UITheme._lum(UITheme.sem("good")) - UITheme._lum(UITheme.sem("bad"))) > 0.08, "good and bad differ in lightness, not only hue")
	_check(absf(UITheme._lum(UITheme.sem("warn")) - UITheme._lum(UITheme.sem("bad"))) > 0.04, "warn and bad differ in lightness")
	_check(ToastFeed.kind_color("bad") == UITheme.sem("bad") and ToastFeed.kind_color("zzz") == UITheme.sem("info"), "toast kinds route through the look")
	_check(PieMenu.cat_color("Mean") == UITheme.sem("mean") and PieMenu.cat_color("Nope") == UITheme.ACCENT, "pie menu categories route through the look")
	# the colour-blind palettes are never toned
	var was := GameSettings.get_bool("colorblind")
	GameSettings.set_value("colorblind", true, false)
	_check(UIU.level_color(0.1) == Color("#d55e00") and UIU.mood_color("happy") == Color("#f0e442"), "colour-blind palettes keep their exact Okabe-Ito colours")
	GameSettings.set_value("colorblind", was, false)
	# the muting applies to the default mood / need ramps
	_check(UIU.mood_color("angry").s < Color("#e5534b").s, "grounded mutes the mood colours")
	_check(UIU.level_color(0.1).s < Color("#e5534b").s, "grounded mutes the need bars")
	# high contrast: pure white text is still available (theme override)
	var was_hc := GameSettings.get_bool("high_contrast")
	GameSettings.set_value("high_contrast", true, false)
	var t := UITheme.build()
	_check(t.get_color("font_color", "Label") == Color.WHITE, "high contrast keeps pure white text in the grounded look")
	GameSettings.set_value("high_contrast", was_hc, false)
