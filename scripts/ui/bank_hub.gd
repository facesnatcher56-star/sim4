class_name BankHub
extends UIDialog
## "Town & Money" (task 13): one window with tabs for the town economy, shops, your business, homes and the bank. Everything here is OPTIONAL.
## The tabs are small builders in shop_dialog / business_dialog / housing_dialog / bank_dialog; every action is a MarketCommand (no state is
## changed from the UI). Opened from the top bar "Money" button or the mailbox "Manage Money" interaction.

const PLAYER_ID := 1
const TABS := [["town", "Town"], ["shops", "Shops"], ["business", "Business"], ["homes", "Homes"], ["bank", "Bank"]]
var tab: String = "town"

func _ready() -> void:
	dialog_width = 520.0
	super._ready()
	UIU.connect_ev("game_event", _on_event)

func _on_event(ev: String, payload: Dictionary) -> void:
	if ev == "open_money":
		tab = "bank"
		show_for(int(payload.get("folk_id", folk_id)))

func build() -> void:
	var f = folk_obj()
	title_label.text = "Town & Money"
	var row := HBoxContainer.new()
	body.add_child(row)
	for t in TABS:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.button_pressed = (tab == t[0])
		b.pressed.connect(_pick.bind(t[0]))
		row.add_child(b)
	if f == null or not MarketEconomy.enabled:
		line("The town economy has not started yet.", 14, UITheme.MUTED)
		return
	match tab:
		"shops": ShopDialog.build(self)
		"business": BusinessDialog.build(self)
		"homes": HousingDialog.build(self)
		"bank": BankDialog.build(self)
		_: _town()

func _pick(t: String) -> void:
	tab = t
	refresh()
	call_deferred("_center")

func hid() -> int:
	var f = folk_obj()
	return int(f.household_id) if f != null else -1

## Run a command for the selected folk, tell the player what happened and rebuild.
func act(action: String, args: Dictionary = {}) -> Dictionary:
	var r: Dictionary = MarketCommand.run(PLAYER_ID, folk_id, action, args)
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
func row_with(text: String, buttons: Array) -> void:
	var h := HBoxContainer.new()
	body.add_child(h)
	var l := UIU.make_label(text, 14)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(dialog_width - 190.0, 0)
	h.add_child(l)
	for b in buttons:
		h.add_child(b)

func _town() -> void:
	var s: Dictionary = MarketEconomy.stats()
	heading("The economy")
	line("%s. Prosperity %s." % [MarketEconomy.phase_label(), _bar(float(s["prosperity"]))], 16)
	for t in MarketEconomy.lines():
		line(t, 13, UITheme.MUTED)
	heading("Where you stand")
	var h: int = hid()
	line("Cash %d coins, savings %d, debts %d. Credit score %d (%s)." % [Economy.balance(h), BankAccounts.balance(h), BankAccounts.debt(h), BankAccounts.credit_score(h),
		BankAccounts.score_label(BankAccounts.credit_score(h))], 14)
	heading("Town news")
	var shown: int = 0
	for i in range(ChronicleHook.recent.size() - 1, -1, -1):
		var c: Dictionary = ChronicleHook.recent[i]
		if str(c["kind"]) in ["economy", "economy_report", "business", "sale", "lottery", "eviction", "foreclosure", "housing"]:
			line("Day %d: %s" % [int(c["day"]), str(c["text"])], 13)
			shown += 1
			if shown >= 6:
				break
	if shown == 0:
		line("Nothing to report yet.", 13, UITheme.MUTED)
	for c2 in BusinessState.closed_log.slice(maxi(BusinessState.closed_log.size() - 2, 0)):
		line("Day %d: %s closed (%s)." % [int(c2["day"]), str(c2["name"]), str(c2["why"])], 13, UITheme.MUTED)
	line("Nothing here is required: the town carries on without you.", 12, UITheme.MUTED)

static func _bar(v: float) -> String:
	var n: int = int(round((v + 1.0) * 5.0))
	return "[" + "#".repeat(clampi(n, 0, 10)) + "-".repeat(10 - clampi(n, 0, 10)) + "]"
