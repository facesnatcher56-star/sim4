class_name StorytellerLogPanel
extends VBoxContainer
## The Storyteller log as a small embeddable panel ("what happened and why", plain words, no spoilers) for the Town panel (12b embeds it; it does not edit
## the panel). Usage: var p := StorytellerLogPanel.new(); parent.add_child(p); p.refresh() (call again when the panel is shown or a day passes).
## Data comes only from Storyteller.log_lines(); `household_only` keeps what touched the player's own household and the town news.

var household_only: bool = false
var max_lines: int = 12
var _title: Label
var _body: Label

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	_title = UIU.make_label("What has been happening", 15)
	add_child(_title)
	_body = UIU.make_label("", 13, UITheme.MUTED)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_body)
	refresh()

func refresh() -> void:
	if _body == null:
		return
	var hid: int = Players.primary_household() if household_only else 0
	var lines: Array = Storyteller.log_lines(max_lines, hid)
	lines.reverse()                                  # newest on top
	_body.text = "Nothing out of the ordinary lately." if lines.is_empty() else "\n".join(PackedStringArray(lines))
