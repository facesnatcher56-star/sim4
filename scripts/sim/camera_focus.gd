class_name CameraFocus
extends RefCounted
## Bridge from a camera to the tiers (task 17.4): where somebody is LOOKING is an extra anchor, so people on a far lot the player watches are simulated in
## full (ACTIVE / NEAR) instead of the statistical or TOWN record. One source per camera: "cam" is the local camera (LotView, also the spectate camera of
## CoopWaiting, which only moves it), "p<id>" is a remote co-op player's camera as the host learns it (CoopProto.CAMERA).
## The focus only moves when the camera has moved MOVE_TILES or more since the last one, so panning does not reclassify the town every frame.

const MOVE_TILES := 6

## A camera looks at `tile`. Returns true when the focus moved.
static func look(source: String, tile: Vector2i) -> bool:
	if Tiers.has_focus(source) and InterestArea.cheb(tile, Tiers.focus_of(source)) < MOVE_TILES:
		return false
	Tiers.set_focus_for(source, tile)
	return true

## Same for a ground position in world units (tile = floor).
static func look_at(source: String, x: float, z: float) -> bool:
	return look(source, Vector2i(int(floorf(x)), int(floorf(z))))

## The camera is gone (leaving the map, a player disconnected).
static func release(source: String) -> void:
	Tiers.clear_focus_for(source)

## The id of a remote player's source.
static func source_of_player(player_id: int) -> String:
	return "p%d" % player_id
