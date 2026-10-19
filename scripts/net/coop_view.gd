class_name CoopView
extends RefCounted
## Client side of the live updates (co-op stage 2): applies a CoopLive delta to the LOCAL copy of the world. The client runs the VIEW only:
## nothing here simulates; folk positions, activities, needs, mood, away flags, coins and toasts come from the host. Positions are set on
## the Folk objects, the existing FolkView walks / animates to them as it always does.
## `apply()` returns "" or the reason a full snapshot is needed (unknown folk, different folk or object count).

static var applied: int = 0
static var last_minute: int = -1

static func apply(d: Dictionary) -> String:
	if d.is_empty() or not d.has("m"):
		return "bad delta"
	var need := ""
	SimEnv.clock().total_minutes = int(d["m"])
	last_minute = int(d["m"])
	applied += 1
	for r in d.get("f", []):
		var f = WorldIface.get_folk(int(r.get("i", -1)))
		if f == null:
			need = "unknown folk"
			continue
		_apply_row(f, r)
	var coins: Dictionary = d.get("c", {})
	for k in coins:
		var hid := int(k)
		WorldIface.coins[hid] = int(coins[k])
		SimEnv.emit("coins_changed", hid, int(coins[k]))
	for t in d.get("t", []):
		SimEnv.emit("notification", str(t[0]), str(t[1]))
	if need == "":
		var n := 0
		for f in WorldIface.all_folk():
			if int(f.household_id) > 0 and not f.has_meta("visitor"):
				n += 1
		if n != int(d.get("nf", n)):
			need = "folk count"
		else:
			var w = WorldIface.world()
			if w != null and "objects" in w and (w.objects as Dictionary).size() != int(d.get("no", (w.objects as Dictionary).size())):
				need = "objects changed"
	SimEnv.emit("game_event", "coop_clock", {})
	return need

static func _apply_row(f, r: Dictionary) -> void:
	f.tile = Vector2i(int(r["x"]), int(r["y"]))
	f.level = int(r.get("l", 0))
	f.posture = str(r.get("po", "stand"))
	f.mood_name = str(r.get("md", f.mood_name))
	f.mood_intensity = int(r.get("mi", 0))
	var aw := str(r.get("aw", ""))
	if aw != "":
		f.set_meta("away", aw)
	elif f.has_meta("away"):
		f.remove_meta("away")
	var needs: Dictionary = r.get("n", {})
	for nid in needs:
		if f.needs.has(nid):
			(f.needs[nid] as Stat).value = float(needs[nid]) + 0.5 - CoopHash.BIAS      # the middle of the whole-number bucket the host sent
	var iid := str(r.get("a", ""))
	if iid == "":
		f.current = null
	elif f.current == null or str(f.current.def_id) != iid or int(f.current.target_id) != int(r.get("t", -1)):
		var it := Interaction.create(iid, f, int(r.get("t", -1)), false)      # a stand-in the view reads (def_id, def, target); it is never ticked here
		f.current = it
