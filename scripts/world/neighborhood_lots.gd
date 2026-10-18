class_name NeighborhoodLots
extends RefCounted
## Swapping the loaded lot (stash / load) and parking folk off-lot while they are elsewhere.

# ------------------------------------------------------------------ lot swapping
static func _save_current() -> void:
	var w = WorldIface.world()
	if w == null:
		return
	Neighborhood.stash[Neighborhood.current_lot] = {"world": w.save_dict(false), "owner": Economy.owner.duplicate(), "placed": Economy.placed_day.duplicate()}

## Store the loaded lot and park every folk that is not among `moving_ids`.
static func _leave_current_lot(moving_ids: Array) -> void:
	_save_current()
	Crowd.clear_npcs()
	_end_situations()
	for f in SysUtil.residents():
		if moving_ids.has(int(f.id)):
			continue
		if not Neighborhood.loc.has(int(f.id)):
			Neighborhood.loc[int(f.id)] = Neighborhood.current_lot
		make_stay(f)
	# every resident that is on this lot but unrecorded
	for f2 in SysUtil.residents():
		if not Neighborhood.loc.has(int(f2.id)):
			Neighborhood.loc[int(f2.id)] = Neighborhood.current_lot

static func _end_situations() -> void:
	for sit in Story.situations:
		if str(sit["state"]) in ["arrive", "mingle", "leave"]:
			for gid in sit["spawned"]:
				var g = SysUtil.folk(int(gid))
				if g != null:
					RelationshipService.sync_folk(g)
					g.current = null
					g.queue.clear()
					SysUtil.world_remove_folk(int(gid))
			sit["state"] = "done"

static func _load_lot(lot_id: String) -> void:
	var w = WorldIface.world()
	Economy.owner.clear()
	Economy.placed_day.clear()
	var saved: Dictionary = Neighborhood.stash.get(lot_id, {})
	if not saved.is_empty():
		w.load_dict(saved["world"])
		Economy.owner = (saved.get("owner", {}) as Dictionary).duplicate()
		Economy.placed_day = (saved.get("placed", {}) as Dictionary).duplicate()
	else:
		var tid: String = Neighborhood.template_of(lot_id)
		NeighborhoodContent.install()
		var ok: bool = LotLoader.apply(tid)
		Neighborhood.last_report = LotLoader.report.duplicate(true)
		if not ok:
			push_warning("Neighborhood: lot %s built with problems: %s" % [lot_id, str(LotLoader.report.get("failed", []))])
		if lot_id != Neighborhood.HOME:
			for o in w.all_objects():
				Economy.owner[int(o.id)] = -1          # community property: never counted in household bills / repossession
				Economy.placed_day[int(o.id)] = SysUtil.day()
	for f3 in w.all_folk():
		w.release_all(int(f3.id))
	Neighborhood.current_lot = lot_id
	Economy.refresh_objects()

# ------------------------------------------------------------------ off-lot ("stay") folk
## Put a folk into the hidden off-lot state at its current `loc`.
static func make_stay(f) -> void:
	if f == null:
		return
	var fid: int = int(f.id)
	var info: Dictionary = Away.info(fid)
	var reason: String = str(info.get("reason", ""))
	if reason == "" and Away.pending.has(fid):
		reason = str((Away.pending[fid] as Dictionary).get("reason", ""))
	if reason in Neighborhood.HELD_REASONS:
		f.set_meta("offlot", str(Neighborhood.loc.get(fid, Neighborhood.current_lot)))
		return
	if reason == Neighborhood.STAY:
		f.set_meta("offlot", str(Neighborhood.loc.get(fid, Neighborhood.current_lot)))
		return
	if reason == Neighborhood.TRAVEL:
		_detach_away(f)
	f.cancel_current("left_lot")
	f.clear_queue()
	WorldIface.world().release_all(fid)
	f.set_meta("offlot", str(Neighborhood.loc.get(fid, Neighborhood.current_lot)))
	f.set_meta("away", Neighborhood.STAY)
	Away.send(f, 99000.0, Neighborhood.STAY, {"label": "At %s" % Neighborhood.label_of(str(Neighborhood.loc.get(fid, Neighborhood.current_lot)))})
	# the pending request is picked up by the director on its next tick; hidden immediately via the metas

## End any away interaction of a folk (stay or travel) without placing it anywhere.
static func _detach_away(f) -> void:
	if f == null:
		return
	var fid: int = int(f.id)
	var reason: String = str(Away.info(fid).get("reason", ""))
	if reason == "" and Away.pending.has(fid):
		reason = str((Away.pending[fid] as Dictionary).get("reason", ""))
	if reason in Neighborhood.HELD_REASONS:
		return
	if Away.pending.has(fid):
		for q in f.queue.duplicate():
			if (q as Interaction).def_id == Away.IID:
				f.queue.erase(q)
		Away.pending.erase(fid)
	if Away.active.has(fid):
		if f.current != null and f.current.def_id == Away.IID:
			f.current.cancel("detached")
		else:
			Away.active.erase(fid)
	if Away.active.has(fid):
		Away.active.erase(fid)
	if f.has_meta("away") and str(f.get_meta("away")) in [Neighborhood.STAY, Neighborhood.TRAVEL]:
		f.remove_meta("away")
		f.remove_buff("away")

static func _clear_stay_marks(f) -> void:
	if f.has_meta("offlot"):
		f.remove_meta("offlot")
	if f.has_meta("away") and str(f.get_meta("away")) == Neighborhood.STAY:
		f.remove_meta("away")

## A stored folk shows up on the loaded lot (entry tile).
static func appear(f) -> void:
	_detach_away(f)
	_clear_stay_marks(f)
	var es: Array = Neighborhood._entry_tiles()
	f.tile = es[int(f.id) % es.size()]
	Neighborhood.loc[int(f.id)] = Neighborhood.current_lot
	Neighborhood._refresh_view(int(f.id))
