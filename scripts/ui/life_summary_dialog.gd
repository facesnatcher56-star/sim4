class_name LifeSummaryDialog
extends UIDialog
## The end-of-life summary window (task 44): sections of short lines, written after the fact. Opens when the character dies; the Household window can
## reopen the last one.

var book: Dictionary = {}

func _ready() -> void:
	dialog_width = 560.0
	super._ready()
	UIU.connect_ev("game_event", _on_event)

func _on_event(ev: String, payload: Dictionary) -> void:
	if ev == "life_summary":
		open_for(int(payload.get("folk_id", -1)))

func open_for(pid: int) -> void:
	book = LifeSummary.books.get(pid, {})
	if book.is_empty():
		return
	show_for(pid)

func build() -> void:
	title_label.text = str(book.get("title", "A life"))
	for s in book.get("sections", []):
		var lines: Array = s["lines"]
		if lines.is_empty():
			continue
		heading(str(s["title"]))
		for l in lines:
			var lab: Label = line(str(l), 13)
			lab.add_theme_color_override("font_color", UITheme.TEXT)
