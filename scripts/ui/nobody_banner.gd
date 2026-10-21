class_name NobodyBanner
extends PanelContainer
## Banner at the top of the screen while nobody plays the household ("nobody left", task 15b). It never blocks the game: the town keeps running.
## Says how long until someone is picked for the player (or that nobody is, when "Pick for me" is off) and opens the choice on a button.
## Shown by the "household_empty" event (sent at the death and every morning), hidden by "head_changed".

var _label: Label

func _ready() -> void:
	UIIdentity.skin(self, "#ff9f43", "frame", 8)
	visible = false
	add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.PANEL, 0.98), 8, UITheme.sem("caution"), 2, 10))
	var v := VBoxContainer.new()
	add_child(v)
	_label = UIU.make_label("", 14)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(320, 0)
	v.add_child(_label)
	var b := Button.new()
	b.text = "Choose who to play"
	b.pressed.connect(func(): SuccessionNobody.prompt(Players.local_id))
	v.add_child(b)
	UIU.connect_ev("game_event", _on_event)

func _on_event(n: String, p: Dictionary) -> void:
	if int(p.get("player_id", -1)) != Players.local_id:
		return
	if n == "household_empty":
		show_days_left(int(p.get("days_left", -1)))
	elif n == "head_changed":
		visible = false

func show_days_left(days_left: int) -> void:
	_label.text = SuccessionText.nobody_banner(days_left)
	visible = true
