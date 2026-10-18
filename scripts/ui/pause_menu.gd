class_name PauseMenu
extends UIDialog
## Esc / the Menu button: Resume, Settings, Save, Load, Help, Quit to Title. Each button emits `chosen(id)`; Hud wires them up.
signal chosen(id: String)
const ITEMS := [["resume", "Resume", "Back to the game"], ["settings", "Settings", "Display, gameplay, accessibility, audio and controls"],
	["save", "Save", "Save to one of your slots"], ["load", "Load", "Load a saved game"], ["share", "Share", "Export or import households and towns, gifts, family cards"], ["help", "Help", "Controls and tips"],
	["quit", "Quit to Title", "Leave this game. Unsaved progress is lost."]]

func _ready() -> void:
	dialog_width = 260.0
	super._ready()

func build() -> void:
	title_label.text = "Paused"
	for it in ITEMS:
		var b := Button.new()
		b.name = "Btn_" + it[0]
		b.text = it[1]
		b.tooltip_text = it[2]
		b.custom_minimum_size = Vector2(0, 36)
		b.pressed.connect(func(): chosen.emit(it[0]))
		body.add_child(b)
