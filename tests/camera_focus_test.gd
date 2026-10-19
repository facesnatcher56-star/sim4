extends RefCounted
## Camera focus (task 17.4): where a camera looks is a Tiers anchor, so folk on a far lot someone watches are simulated, not TOWN / STATISTICAL.
## Local camera ("cam"), a remote co-op player's camera (CAMERA message -> "p<id>"), the spectate camera, throttle, release, save.

const HoodKit := preload("res://tests/hood_kit.gd")
const Kit := preload("res://tests/coop_kit.gd")
var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

var _next := 9500

func _npc(tile: Vector2i, lot: String):
	_next += 1
	var f := Folk.create("C%d" % _next, [], _next)
	f.household_id = -1
	f.set_meta("visitor", true)
	f.set_meta("staff", "tester")
	f.set_meta("staff_lot", lot)
	SysUtil.world_add_folk(f, tile)
	f.idle_until_min = CrowdDrive.NEVER
	return f

func _far_lot(from: Vector2i) -> String:
	var best := ""
	var bd := -1
	for lot_id in Neighborhood.lot_ids():
		var rc := NeighborhoodLots.rect_of(lot_id)
		if rc.size == Vector2i.ZERO:
			continue
		var d := InterestArea.cheb(rc.position + rc.size / 2, from)
		if d > bd:
			bd = d
			best = lot_id
	return best if bd >= 70 else ""

func run() -> Array:
	fails = []
	HoodKit.teardown()
	var folk: Array = HoodKit.new_game("classic", 21, 21)
	var me = folk[0]
	Tiers.refresh()
	var lot := _far_lot(me.tile)
	_check(lot != "", "the classic map has a lot 70+ tiles away")
	if lot == "":
		HoodKit.teardown()
		return fails
	var rc := NeighborhoodLots.rect_of(lot)
	var mid: Vector2i = rc.position + rc.size / 2
	var far = _npc(mid, lot)
	Tiers.refresh()
	var before: int = Tiers.of(far)
	_check(before != Tiers.ACTIVE, "without a camera there, the far lot's person is not ACTIVE (%s)" % Tiers.NAMES[before])
	var base_anchors: int = Tiers.anchors.size()

	# --- the local camera
	_check(CameraFocus.look("cam", mid), "the camera looks at the far lot: the focus moved")
	Tiers.refresh()
	_check(Tiers.anchors.size() == base_anchors + 1, "the focus is one more anchor")
	_check(Tiers.of(far) == Tiers.ACTIVE, "the person where the camera looks is simulated in full (%s)" % Tiers.NAMES[Tiers.of(far)])
	# --- throttle: small camera moves do not move the focus (no reclassification of the town per pixel)
	_check(not CameraFocus.look("cam", mid + Vector2i(CameraFocus.MOVE_TILES - 1, 0)), "a small pan keeps the focus")
	_check(CameraFocus.look("cam", mid + Vector2i(CameraFocus.MOVE_TILES, 0)), "a pan of MOVE_TILES moves it")
	_check(Tiers.focus_of("cam") == mid + Vector2i(CameraFocus.MOVE_TILES, 0), "the focus tile follows")
	# --- release: the camera is gone, the person drops back (after the demotion delay)
	CameraFocus.release("cam")
	Tiers.refresh()
	_check(Tiers.anchors.size() == base_anchors and not Tiers.has_focus("cam"), "released: the anchor is gone")
	for i in 15:
		SimEnv.clock().advance_minutes(1)
	Tiers.refresh()
	_check(Tiers.of(far) != Tiers.ACTIVE, "after the demotion delay the person is off screen again (%s)" % Tiers.NAMES[Tiers.of(far)])

	# --- two cameras (host + a remote player): both are anchors, in a fixed order
	CameraFocus.look("cam", mid)
	CameraFocus.look(CameraFocus.source_of_player(2), Vector2i(3, 3))
	Tiers.refresh()
	_check(Tiers.anchors.size() == base_anchors + 2, "local and remote cameras are both anchors")
	var sig1: int = Tiers._anchor_sig
	Tiers._foci = {"p2": Vector2i(3, 3), "cam": mid}                    # same sources, other insertion order
	Tiers.refresh()
	_check(Tiers._anchor_sig == sig1, "the anchor order does not depend on insertion order")

	# --- save: only the local camera is saved; remote ones are not
	var d: Dictionary = Tiers.to_dict()
	_check((d["focus"] as Array).size() == 2 and int(d["focus"][0]) == mid.x, "the local camera focus is in the save")
	Tiers.from_dict(d)
	_check(Tiers.has_focus("cam") and not Tiers.has_focus("p2"), "a load restores the local focus and forgets remote cameras")
	CameraFocus.release("cam")

	# --- co-op: a client tells the host where its camera is
	CoopProto.build_override = "test-build"
	var n := Kit.FakeNet.new()
	var c := n.add_client(10, "Sam")
	n.pump()
	_check(c.state == "synced", "client synced")
	var pid: int = c.player_id
	c.send_camera(mid)
	n.pump()
	_check(Tiers.has_focus(CameraFocus.source_of_player(pid)) and Tiers.focus_of(CameraFocus.source_of_player(pid)) == mid, "the host holds the remote player's camera focus")
	c.send_camera(Vector2i(100000, -50))
	n.pump()
	var w = WorldIface.world()
	var t2: Vector2i = Tiers.focus_of(CameraFocus.source_of_player(pid))
	_check(t2.x == int(w.width) - 1 and t2.y == 0, "a camera outside the map is clamped to it (%s)" % str(t2))
	n.host.peer_disconnected(10, n.now)
	n.advance(1.0)
	_check(not Tiers.has_focus(CameraFocus.source_of_player(pid)), "the remote focus is released when the player leaves")
	CoopProto.build_override = ""
	CameraFocus.release("cam")
	HoodKit.teardown()
	return fails
