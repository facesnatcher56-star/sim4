class_name ShareHub
extends UIDialog
## "Share" window (Pause menu): export / import a household or a whole town, gifts and letters, family-history cards.
## Files live in the exports folder, whose path is shown on every page. The pages are small builders (share_page_*.gd).

var page := "menu"
var note := ""                  # result of the last action, shown at the top of the page
var choice := ""                # selected file / household key on the current page
var preview: Dictionary = {}    # validated data of the selected file (import pages)
var card: Dictionary = {}       # card shown on the card page

const PAGES := [["exp_house", "Export a household", "Save a family and its history to a file a friend can open"],
	["imp_house", "Import a household", "A friend's family moves into your town as townies"],
	["exp_town", "Export this town", "Save the town and its Chronicle to share"],
	["imp_town", "Import a town", "Open a friend's town as a NEW save slot"],
	["inbox", "Gifts & letters", "Read what was left for you, or leave something in a friend's town file"],
	["card", "Family-history card", "A shareable card for a household"]]

func _ready() -> void:
	dialog_width = 540.0
	super._ready()

func go(p: String) -> void:
	page = p
	choice = ""
	preview = {}
	refresh()
	call_deferred("_center")

func show_for(fid: int) -> void:
	page = "menu"
	note = ""
	choice = ""
	preview = {}
	super.show_for(fid)

func build() -> void:
	title_label.text = "Share"
	if note != "":
		line(note, 14, UITheme.ACCENT)
	if page == "menu":
		for p in PAGES:
			var b := Button.new()
			b.name = "Btn_" + p[0]
			b.text = p[1]
			b.tooltip_text = p[2]
			b.custom_minimum_size = Vector2(0, 34)
			b.pressed.connect(go.bind(p[0]))
			body.add_child(b)
		line("Files are plain text. Anything you open is checked first, and only known, safe things are used.", 12, UITheme.MUTED)
		return
	var back := Button.new()
	back.name = "Btn_back"
	back.text = "< Back"
	back.pressed.connect(func():
		note = ""
		go("menu"))
	body.add_child(back)
	match page:
		"exp_house", "imp_house":
			SharePageHouse.build(self)
		"exp_town", "imp_town":
			SharePageTown.build(self)
		"inbox":
			SharePageMail.build(self)
		"card":
			SharePageCard.build(self)

func folder_line() -> void:
	line("Folder: " + ShareFile.shown_path(), 12, UITheme.MUTED)

func pick_button(text: String, key: String) -> Button:
	var b := Button.new()
	b.text = ("> " if key == choice else "") + text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func():
		choice = key
		preview = {}
		refresh()
		call_deferred("_center"))
	body.add_child(b)
	return b

func action_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 32)
	b.pressed.connect(cb)
	body.add_child(b)
	return b

func say(text: String) -> void:
	note = text
	refresh()
	call_deferred("_center")
