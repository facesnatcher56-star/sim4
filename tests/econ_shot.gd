extends SceneTree
## Screenshot helper (not a test): godot --path . --resolution 1280x720 --script res://tests/econ_shot.gd -- <tab> out.png
## Tabs: town | shops | business | homes | bank
var _frames := 0
var _main: Node = null
var _out := "user://econ.png"
var _tab := "town"

func _process(_d: float) -> bool:
	if _main == null:
		var args := OS.get_cmdline_user_args()
		if args.size() > 0:
			_tab = args[0]
		if args.size() > 1:
			_out = args[1]
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	_frames += 1
	var hud = _main.hud
	if _frames == 5:
		load("res://scripts/ui/ui_prefs.gd").set_flag("tips_seen", true)
		_main.start_new_game(_main.default_household())
	if _frames == 30 and _main.playing:
		var W = root.get_node("World")
		var f = W.all_folk()[0]
		var hid: int = int(f.household_id)
		WorldIface.coins[hid] = 6000
		if _tab == "business":
			BusinessCmd.open(hid, "cafe", "cafe", "rent", "Rowe's Cafe")
			BusinessCmd.open(hid, "cafe", "cafe", "rent", "")
		for d in range(2, 25):
			root.get_node("Clock").total_minutes = (d - 1) * 1440 + 480
			MarketTick.on_day(d)
		if _tab == "bank":
			BankAccounts.take_loan(hid, 600)
			BankAccounts.deposit(hid, 300)
		hud.money_hub.tab = _tab
		hud.money_hub.show_for(f.id)
	if _frames == 90:
		var img := root.get_texture().get_image()
		img.save_png(_out)
		print("saved ", _out, " ", img.get_size())
		quit(0)
	return false
