class_name TownLawDialog
extends UIDialog
## The Town Law book (task 20): every charge by class with a description, bail, sentence range and what the court weighs. Opened from the case
## board, the help screen and the "Read the Town Law" interaction. Data: TownLaw (justice.json).

func _ready() -> void:
	dialog_width = 600.0
	super._ready()

## Show the book on a node already in the tree (creates it once as a sibling of `from`).
static func open_from(from: Node) -> void:
	var host: Node = from.get_parent() if from.get_parent() != null else from
	for c in host.get_children():
		if c is TownLawDialog:
			(c as TownLawDialog).show_for(-1)
			return
	var d := TownLawDialog.new()
	host.add_child(d)
	d.show_for(-1)

func build() -> void:
	title_label.text = "Town Law"
	line("Every charge in town, from small offences to the gravest crimes. The court starts from the usual range and then weighs what happened: a repeat offence, injuries, a child or older victim, violence at home or a broken order make it heavier; a first offence, a guilty plea, provocation and remorse make it lighter.", 12, UITheme.MUTED)
	var shown_class: String = ""
	for e in TownLaw.entries():
		if str(e["class"]) != shown_class:
			shown_class = str(e["class"])
			heading(str(TownLaw.CLASS_LABEL[shown_class]))
			line(str(TownLaw.CLASS_BLURB[shown_class]), 12, UITheme.MUTED)
		_entry(e)

func _entry(e: Dictionary) -> void:
	line("%s  (%s)%s" % [str(e["label"]), TownLaw.grade_label(e), "  - rare in town so far" if bool(e["stub"]) else ""], 14, UITheme.ACCENT)
	line(str(e["description"]), 12)
	line("Usual sentence: %s%s. Bail %s. %s" % [str(e["sentence"]), "; also " + str(e["also"]) if str(e["also"]) != "" else "", str(e["bail"]) + " coins" if int(e["bail"]) > 0 else "none",
		"Heard without a jury." if not bool(e["jury"]) else "Heard by a jury."], 12, UITheme.MUTED)
	if str(e["aggravating"]) != "":
		line("Heavier for: " + str(e["aggravating"]) + ".", 11, UITheme.MUTED)
	if str(e["mitigating"]) != "":
		line("Lighter for: " + str(e["mitigating"]) + ".", 11, UITheme.MUTED)
	line("What makes it this charge: %s. %s%s" % [str(e["elements"]), str(e["record"]), " Closes careers: " + str(e["bans"]) + "." if str(e["bans"]) != "" else ""], 11, UITheme.MUTED)
