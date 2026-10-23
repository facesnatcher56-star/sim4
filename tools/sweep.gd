extends SceneTree
## A "try everything" playtest (not a test suite): a new solo game, then every window and tab, the Myself menu, every kind of object in town and every
## person interaction, each pressed through the real pie menu. The work is in sweep_run.gd (a Node loaded once the game's autoloads exist).
##   powershell -File tools/quiet_godot.ps1 --script res://tools/sweep.gd -- <out dir> [ui] [self] [objects] [social]      (no phase names = all)
## Log lines start with a tag: MENU, OFF (a greyed entry and why), ACT (one per action), ODD (something that looks wrong), TOAST, SAY, THINK, ASK, SHOT.

func _process(_d: float) -> bool:
	if root.get_node_or_null("Sweep") == null:
		var path := "res://tools/sweep_run.gd"
		for a in OS.get_cmdline_user_args():
			if str(a).begins_with("run="):          # run=<script>: a one-off probe built the same way (a Node loaded once the autoloads exist)
				path = str(a).substr(4)
		var scr = load(path)
		if scr == null or not scr.can_instantiate():          # a script that doesn't compile: stop, don't spin
			print("SWEEP could not load " + path)
			quit(2)
			return true
		var n: Node = scr.new()
		n.name = "Sweep"
		root.add_child(n)
	return false
