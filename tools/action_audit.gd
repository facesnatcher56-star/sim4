extends SceneTree
## Task 33 audit (view data only): every interaction, the clip it resolves to and whether that is a generic one (tests/action_visual_kit.gd).
##   powershell -File tools/godot_guard.ps1 -Seconds 300 -Args "--headless","--path",".","--script","res://tools/action_audit.gd"
## Writes docs/ACTION_VISUALS.md (the work list: every interaction that was generic before task 33, grouped by object / tag, with its clip before, the
## 3-day frequency from docs/act33/audit_before.json and the clip, prop and particles now). Extra args after `--`:
##   --json=<path>   also write the audit as JSON {rows, total, generic, freq}
##   --freq          play a fresh 3-day run for the frequencies (the committed baseline already has them: same seed, same run)
const BEFORE := "res://docs/act33/audit_before.json"
const OUT := "res://docs/ACTION_VISUALS.md"
var _FP: GDScript
var _FX: GDScript
var _FV: GDScript          # loaded at run time: a SceneTree script is parsed before the autoloads these classes use exist


func _arg(key: String) -> String:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with(key + "="):
			return str(a).substr(key.length() + 1)
	return ""


func _process(_d: float) -> bool:
	_FP = load("res://scripts/world/folk_props.gd")
	_FX = load("res://scripts/world/folk_fx.gd")
	_FV = load("res://scripts/world/folk_view.gd")
	var AK: GDScript = load("res://tests/action_visual_kit.gd")
	var rows: Dictionary = AK.rows()
	var generic_now := 0
	for id in rows:
		if bool(rows[id]["generic"]):
			generic_now += 1
	var props_of := {}
	for id in rows:
		var r: Dictionary = rows[id]
		var clip: String = str(r["clips"][0])
		var what: Array = _FP.props_for(str(id), r["tags"], clip)
		var fx: String = _FX.fx_for(str(id), r["tags"], clip)
		var done: String = _FX.done_for(str(id), r["tags"])
		var parts: Array = []
		if not what.is_empty():
			parts.append(" + ".join(what))
		if fx != "":
			parts.append("fx " + fx)
		if done != "":
			parts.append("on finish " + done)
		props_of[id] = ", ".join(parts)
	load("res://tests/sim_testkit.gd").teardown()
	var before: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BEFORE))
	var freq: Dictionary = before.get("freq", {})
	if OS.get_cmdline_user_args().has("--freq"):
		freq = AK.freq(3)
	var jp := _arg("--json")
	if jp != "":
		var f := FileAccess.open(jp, FileAccess.WRITE)
		f.store_string(JSON.stringify({"rows": rows.keys(), "total": rows.size(), "generic": generic_now, "freq": freq}, "\t"))
		f.close()
	_write_md(before, rows, props_of, freq, generic_now)
	print("audit: %d interactions, generic before %d (%.1f%%), now %d (%.1f%%) -> %s" % [rows.size(), int(before["generic"]), 100.0 * float(before["share"]), generic_now, 100.0 * generic_now / rows.size(), OUT])
	quit(0)
	return true


func _write_md(before: Dictionary, rows: Dictionary, props_of: Dictionary, freq: Dictionary, generic_now: int) -> void:
	var brow: Dictionary = before["rows"]
	var work: Array = []
	for id in brow:
		if bool(brow[id]["generic"]) and rows.has(id):
			work.append(str(id))
	work.sort_custom(func(a, b):
		var ga := str(brow[a]["group"])
		var gb := str(brow[b]["group"])
		if ga != gb:
			return ga < gb
		return int(freq.get(a, 0)) > int(freq.get(b, 0)) or (int(freq.get(a, 0)) == int(freq.get(b, 0)) and str(a) < str(b)))
	var t: Array = []
	t.append("# Action visuals (task 33): what every interaction shows\n")
	t.append("Owner: \"a lot of stuff in game shows the same default model animation and nothing changes. Example: watering plants.\" This file is the audit and the work list; it is written by `tools/action_audit.gd` (rerun it after changing `data/animation_map.json`, `data/animation_props.json` or `blender/folk_action_poses.py`).\n")
	t.append("**Generic clip** = the clip an interaction resolves to is `Use_Stand`, `Idle`, `Talk` or `Sit_Idle` (the posture fallback), looked up with `FolkClipRules` for the pose of the object's use slot (`tests/action_visual_kit.gd`). `generic_ok` in `data/animation_map.json` lists the few interactions allowed to stay generic: `go_here` (a walk, drawn by locomotion), `sys_away` / `sys_staff` (off-lot markers) and `sit_chair` (plain sitting).\n")
	t.append("| | interactions | generic clip | share |\n|---|---|---|---|")
	t.append("| before task 33 | %d | %d | %.1f%% |" % [int(before["total"]), int(before["generic"]), 100.0 * float(before["share"])])
	var raw := 0
	for id in rows:
		if bool(rows[id]["raw_generic"]):
			raw += 1
	t.append("| now | %d | %d | %.1f%% |" % [rows.size(), generic_now, 100.0 * generic_now / rows.size()])
	t.append("| now, with the `generic_ok` allow-list counted as generic | %d | %d | %.1f%% |\n" % [rows.size(), raw, 100.0 * raw / rows.size()])
	t.append("Tests: `tests/action_visuals_test.gd` (fast: share under 15%, the everyday actions have a prop or particles, particle data complete, a watering folk shows can + water arc and a finished chore sparkles); `tests/action_visuals_longrun_test.gd` (slow: none of the 30 most frequent interactions of a 3-day run is generic). Screenshots: `docs/act33/shot_*.png` (`tests/act33_shot.gd`).\n")
	t.append("## Work list (everything that was generic before)\n")
	t.append("Frequency = how often the interaction started in a 3-day run (classic start, seed 4242, all folk). Props hang on a hand bone (`FolkProps`), particles are `FolkFx`; both are view only.\n")
	t.append("| interaction id | object / tag | clip before | starts / 3 days | clip now | prop / particles now |\n|---|---|---|---|---|---|")
	for id in work:
		var r: Dictionary = rows[id]
		t.append("| %s | %s | %s | %d | %s | %s |" % [id, str(brow[id]["group"]), ", ".join(brow[id]["clips"]), int(freq.get(id, 0)), ", ".join(r["clips"]), str(props_of.get(id, ""))])
	t.append("\n## Still on a generic clip\n")
	var left: Array = []
	for id in rows:
		if bool(rows[id]["generic"]):
			left.append(str(id))
	var ok: Array = _FV.anim_map().get("generic_ok", [])
	t.append("Counted as generic: %s.\n" % (", ".join(left) if not left.is_empty() else "none"))
	t.append("Allowed to stay generic (`generic_ok`): %s.\n" % ", ".join(ok))
	t.append("## New clips (blender/folk_action_poses.py, 29)\n")
	t.append("Pour, Wipe, Mop, Repair (crouched), Phone_Call, Phone_Text (+ Sit_ twins), Eat, Dig (crouched), Bend, Fish, Lift, Write (+ Sit_Write), Brush_Teeth, Sing, Cradle, Look, Think (+ Sit_Think), Reach, Strum, Sit_Piano, Balance, Relax (+ Sit_Relax), Speech, Aim. Sitting folk get the `Sit_` twin through `sit_substitute`.\n")
	t.append("## Not covered\n")
	t.append("- Objects changing (soil darkening, dirty dish, broken look, fridge door, burner glow, TV flicker, made bed, crops growing) is task 33.3 (`state33b`); the progress ring above the head is 33.4.\n- Some clips are shared by several different actions where a dedicated animation would not read differently (Reach: grabbing from a fridge, a vending machine, a shelf, a lamp; Look: gazing, scanning, stargazing).\n- Props are low-poly primitives (boxes, cylinders) in the hands, not modelled meshes; the sports and vacation interactions (skiing, surfing, hiking) have a pose but no equipment.\n- Social interactions keep the Talk / Laugh / Wave cycles: talking is what they are.\n")
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(t))
	f.close()
