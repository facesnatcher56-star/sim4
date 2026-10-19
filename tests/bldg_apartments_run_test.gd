extends RefCounted
## SLOW: an apartment building with several households runs for game days. Each household holds a flat (locked door, its own furniture),
## folk sleep / eat / wash in THEIR flat, walk the corridor, take the stairs or the lift, never use a neighbour's furniture, stay on valid
## tiles of valid floors, and nothing errors. (Runner: SLOW list; TestFixture.fast shortens it to a day.)

const Kit = preload("res://tests/hood_kit.gd")

var fails: Array = []
var own_uses: int = 0
var foreign_uses: int = 0
var level_changes: int = 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func run() -> Array:
	fails = []
	own_uses = 0
	foreign_uses = 0
	level_changes = 0
	var folk: Array = Kit.new_game("small", 777, 1)
	var W: Node = Kit.world()
	var units: Array = ApartmentUnits.units_of("apartments")
	_check(units.size() >= 8, "an apartment block (%d flats)" % units.size())
	if units.size() < 8:
		return fails
	# four households of two in flats on different floors (hid 2..5)
	var picks: Array = []
	var floors_used: Dictionary = {}
	for u in units:
		if not floors_used.has(int(u["level"])) and picks.size() < 4:
			floors_used[int(u["level"])] = true
			picks.append(u)
	for u in units:
		if picks.size() < 4 and not picks.has(u):
			picks.append(u)
	var movers: Array = []
	var hid := 2
	for u in picks:
		Economy.start_funds(hid)
		ApartmentUnits.assign(u, hid)
		var spot := _free_tile(W, u)
		for nm in ["A%d" % hid, "B%d" % hid]:
			var f := Folk.create(nm, ["neat", "social"])
			f.household_id = hid
			W.add_folk(f, spot, int(u["level"]))
			movers.append(f)
		hid += 1
	Aging.ensure_all()
	Genetics.ensure_all()
	Goals.ensure_all()
	Economy.refresh_objects()
	_check(ApartmentUnits.units_of_household(3).size() == 1, "households hold one flat each")
	var days: int = TestFixture.pick(3, 1)
	var steps: int = days * 24 * 6
	for step in steps:
		Kit.run(10)
		_audit(W, movers)
	print("  [apartments] %d days, %d households: %d uses of own flat furniture, %d of another's, %d floor changes" % [days, picks.size(), own_uses, foreign_uses, level_changes])
	_check(foreign_uses == 0, "nobody used a neighbour's furniture (%d)" % foreign_uses)
	_check(own_uses > 8, "folk used their own flats (%d)" % own_uses)
	_check(level_changes > 0 or TestFixture.fast, "somebody changed floors on foot (%d)" % level_changes)
	for f in movers:
		_check(SysUtil.folk(int(f.id)) != null, "%s is still around" % f.name)
	for f in movers:
		_check(WorldIface.level_valid(f.tile, int(f.level)), "%s is on a valid floor (level %d, lot %s)" % [f.name, f.level, NeighborhoodLots.lot_at(f.tile)])
	Kit.teardown()
	return fails


func _free_tile(W: Node, u: Dictionary) -> Vector2i:
	var rc: Rect2i = u["rect"]
	for y in range(rc.position.y, rc.end.y):
		for x in range(rc.position.x, rc.end.x):
			var t := Vector2i(x, y)
			if W.levels.is_walkable(t, int(u["level"])) and W.object_at(t, int(u["level"])) == null:
				return t
	return rc.position


var _last_level: Dictionary = {}


func _audit(W: Node, movers: Array) -> void:
	for f in movers:
		var fid := int(f.id)
		if _last_level.has(fid) and int(_last_level[fid]) != int(f.level):
			level_changes += 1
		_last_level[fid] = int(f.level)
		if f.current != null and f.current.obj != null:
			var o = f.current.obj
			var u: Dictionary = ApartmentUnits.unit_at(o.tile, int(o.level))
			if not u.is_empty() and not bool(f.current.def_id in ["go_here"]):
				if ApartmentUnits.owner_of(u) == int(f.household_id):
					own_uses += 1
				else:
					foreign_uses += 1
