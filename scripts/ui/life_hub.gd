class_name LifeHub
extends UIDialog
## "Town life" (task 14): one window for the places of the town (school, college, clinic, restaurants, cinema ...), what the selected person is studying,
## their health, and the job board. Everything here is OPTIONAL. The tabs are small builders (LifeHubPlaces, LifeHubStudy, LifeHubJobs); every action is a
## command through the command layer (Commands.run action "life"), never a change made by the UI. Opened from the top bar "Town" button.

const PLAYER_ID := 1
const TABS := [["places", "Places"], ["study", "Study"], ["health", "Health"], ["pets", "Pets"], ["news", "News"]]
var tab: String = "places"
var place_id: String = ""
var kind: String = ""

func _ready() -> void:
	if dialog_width == 460.0:
		dialog_width = 540.0
	super._ready()

func build() -> void:
	title_label.text = "Town life"
	var row := HBoxContainer.new()
	body.add_child(row)
	for t in TABS:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.button_pressed = (tab == t[0])
		b.pressed.connect(_pick.bind(t[0]))
		row.add_child(b)
	if folk_obj() == null:
		line("Pick somebody first.", 14, UITheme.MUTED)
		return
	match tab:
		"study": LifeHubStudy.build(self)
		"health": LifeHubHealth.build(self)
		"pets": LifeHubPets.build(self)
		"phone": LifeHubPhone.build(self)
		"news": LifeHubMedia.build(self)
		_: LifeHubPlaces.build(self)

func _pick(t: String) -> void:
	tab = t
	refresh()
	call_deferred("_center")

## Run a life command for the selected person, say what happened and rebuild.
func act(action: String, args: Dictionary = {}) -> Dictionary:
	var r: Dictionary = Commands.run({"player_id": PLAYER_ID, "folk_id": folk_id, "action": "life", "args": {"action": action, "args": args}})
	if not bool(r.get("ok", false)) and str(r.get("reason", "")) != "":
		UIU.notify(str(r["reason"]), "warn")
	refresh()
	call_deferred("_center")
	return r

func button(text: String, tip: String, fn: Callable, enabled: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.disabled = not enabled
	b.pressed.connect(fn)
	return b

## A line of text with buttons on the right.
func row_with(text: String, buttons: Array, muted: bool = false) -> void:
	var h := HBoxContainer.new()
	body.add_child(h)
	var l := UIU.make_label(text, 14)
	if muted:
		l.add_theme_color_override("font_color", UITheme.MUTED)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(dialog_width - 200.0, 0)
	h.add_child(l)
	for b in buttons:
		h.add_child(b)
