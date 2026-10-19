class_name HelpDialog
extends UIDialog
## Controls reference (F1 or the "?" button).
const KEYS := [
	["Camera", [["W A S D", "Pan the camera"], ["Q / E", "Rotate the view"], ["Mouse wheel", "Zoom in and out"], ["Middle mouse drag", "Pan the camera"],
		["Z or Tab", "Cycle wall view (cut-away / walls up / down)"]]],
	["Time", [["Space", "Pause or resume"], ["1 / 2 / 3", "Normal, fast, fastest speed"]]],
	["Folk", [["Click a Folk", "Select them. Clicking someone from another household opens the social menu instead"], ["Click an object", "Open the menu of things the selected Folk can do with it"],
		["Right-click the ground", "Send the selected Folk there (Go Here)"], ["Click a queue chip", "Cancel that task"], ["Folk buttons (bottom-left)", "Switch between your household"]]],
	["Windows", [["B", "Build / Buy mode"], ["M", "Neighbourhood map and travel"], ["F1 or ?", "This help"], ["Esc", "Close menus and dialogs"]]],
	["Build / Buy", [["R", "Rotate the item you are placing"], ["Ctrl+Z", "Undo the last build action"], ["Esc", "Go back to selecting"]]],
]

func _ready() -> void:
	dialog_width = 480.0
	super._ready()

func build() -> void:
	title_label.text = "Controls"
	for sec in KEYS:
		heading(str(sec[0]))
		for kv in sec[1]:
			var row := HBoxContainer.new()
			body.add_child(row)
			var k := UIU.make_label(key_text(str(kv[0])), 14, UITheme.ACCENT)
			k.custom_minimum_size = Vector2(170, 0)
			row.add_child(k)
			var d := UIU.make_label(str(kv[1]), 14)
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			d.custom_minimum_size = Vector2(260, 0)
			d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(d)
	var law := Button.new()
	law.text = "Town Law: every charge and sentence"
	law.pressed.connect(func(): TownLawDialog.open_from(self))
	body.add_child(law)
	var again := Button.new()
	again.text = "Show the welcome tips again"
	again.pressed.connect(func():
		UIPrefs.set_flag("tips_seen", false)
		hide_dialog()
		tips_requested.emit())
	body.add_child(again)

signal tips_requested

## Shortcuts the player can rebind show their current keys (Settings > Controls); everything else is printed as written.
const ACTION_KEYS := {"W A S D": ["sim_pan_up", "sim_pan_left", "sim_pan_down", "sim_pan_right"], "Q / E": ["sim_rotate_left", "sim_rotate_right"],
	"Space": ["sim_pause"], "1 / 2 / 3": ["sim_speed_1", "sim_speed_2", "sim_speed_3"], "B": ["sim_build"], "M": ["sim_map"],
	"R": ["sim_build_rotate"], "Ctrl+Z": ["sim_undo"]}

static func key_text(label: String) -> String:
	if not ACTION_KEYS.has(label):
		return label
	var parts: Array = []
	for a in ACTION_KEYS[label]:
		parts.append(SettingsKeys.binding_text(a))
	return " ".join(parts) if label == "W A S D" else " / ".join(parts)