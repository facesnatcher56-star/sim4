class_name PlayerLots
extends RefCounted
## Which lot belongs to which player (co-op, task 24C stage 2). The host's own lot is the map's "home" region (player 1). A joining
## player gets a CONVERTED townie home: one of the three neighbour houses (townie_a / b / c; not the apartment block, not venues, not the
## park). The region gets `pid` (saved with the regions) and its neighbours the townies who lived there move to the remaining townie homes
## (Neighborhood.residents_of skips claimed lots). Build rules: a player may only build on a lot whose region `pid` is theirs
## (`build_ok`, used by WorldRegions.can_build); `acting` is the player whose command is running right now (Commands.run sets it).
## Solo games never claim anything, so nothing changes for them.

const MAX_CLAIMS := 3                       # + the host's home = 4 players
const NOT_CLAIMABLE := ["apartments"]       # lot ids that can never be converted

## Player whose command is being applied (-1 = no command running: this machine's own player).
static var acting: int = -1

static func acting_player() -> int:
	return acting if acting > 0 else Players.local_id

static func _regions():
	var w = WorldIface.world()
	return w.regions if (w != null and "regions" in w) else null

## Player id owning a region (the home region = player 1), 0 = nobody.
static func region_owner(r: Dictionary) -> int:
	if r.is_empty():
		return 0
	if r.has("pid"):
		return int(r["pid"])
	return Players.LOCAL if str(r.get("kind", "")) == "home" and str(r.get("owner", "")) == "player" else 0

## WorldRegions.can_build hook: the region at `rid` is buildable by the acting player.
static func build_ok(rid: int) -> bool:
	var rg = _regions()
	if rg == null or rid == WorldRegions.NONE:
		return false
	return region_owner(rg.region(rid)) == acting_player()

## Lot ids a joining player could be given right now (free converted-townie-home candidates), in map order.
static func free_lots() -> Array:
	var out: Array = []
	var rg = _regions()
	if rg == null:
		return out
	for l in Neighborhood.lots():
		var id := str(l["id"])
		if str(l.get("type", "")) != "townie_home" or NOT_CLAIMABLE.has(id):
			continue
		if region_owner(rg.by_lot(id)) == 0:
			out.append(id)
	return out

static func claimed_count() -> int:
	var n := 0
	for l in Neighborhood.lots():
		var rg = _regions()
		if rg != null and str(l.get("type", "")) == "townie_home" and region_owner(rg.by_lot(str(l["id"]))) > 0:
			n += 1
	return n

static func is_claimed(lot_id: String) -> bool:
	var rg = _regions()
	return rg != null and str(Neighborhood.lot(lot_id).get("type", "")) == "townie_home" and region_owner(rg.by_lot(lot_id)) > 0

## Lot id of a player's home ("home" for the host's own lot, "" if the player has no lot).
static func lot_of(player_id: int) -> String:
	var rg = _regions()
	if rg == null:
		return Neighborhood.HOME if player_id == Players.LOCAL else ""
	if player_id == Players.LOCAL:
		return Neighborhood.HOME
	for r in rg.regions.values():
		if int(r.get("pid", 0)) == player_id:
			return str(r["lot"])
	return ""

## Lot id a household lives on: its player's own lot in co-op, Neighborhood.HOME for the host, NPC households and solo games.
## Everything that sends someone "home" (commute return, hospital discharge, holiday return, visits, parties) asks this, not Neighborhood.HOME.
static func home_of_household(household_id: int) -> String:
	var pid: int = Players.player_of(household_id)
	if pid <= Players.LOCAL:
		return Neighborhood.HOME
	var lot: String = lot_of(pid)
	return lot if lot != "" else Neighborhood.HOME

static func home_of(f) -> String:
	return Neighborhood.HOME if f == null else home_of_household(int(f.household_id))

## Player whose lot this is (0 = none / venue / street).
static func player_of_lot(lot_id: String) -> int:
	var rg = _regions()
	if rg == null:
		return 0
	if lot_id == Neighborhood.HOME:
		return Players.LOCAL
	return region_owner(rg.by_lot(lot_id))

## Give `lot_id` (or the first free one) to the player. Returns {ok, msg, lot}.
static func claim(player_id: int, lot_id: String = "") -> Dictionary:
	var rg = _regions()
	if rg == null:
		return {"ok": false, "msg": "This town has no lots to give out.", "lot": ""}
	if lot_of(player_id) != "":
		return {"ok": true, "msg": "", "lot": lot_of(player_id)}
	var free := free_lots()
	if free.is_empty() or claimed_count() >= MAX_CLAIMS:
		return {"ok": false, "msg": "There is no free home left in this town.", "lot": ""}
	if lot_id == "" or not free.has(lot_id):
		lot_id = str(free[0])
	var r: Dictionary = rg.by_lot(lot_id)
	r["pid"] = player_id
	r["owner"] = "player"
	return {"ok": true, "msg": "", "lot": lot_id}

## Frees a lot again (a player who left for good).
static func release(player_id: int) -> void:
	var rg = _regions()
	if rg == null or player_id == Players.LOCAL:
		return
	for r in rg.regions.values():
		if int(r.get("pid", 0)) == player_id:
			r.erase("pid")
			r["owner"] = "npc"

## Objects standing on a lot now belong to the household living there.
static func hand_over_objects(lot_id: String, household_id: int) -> int:
	var rc := NeighborhoodLots.rect_of(lot_id)
	var n := 0
	for o in SysUtil.all_world_objects():
		if rc.has_point(o.tile):
			Economy.owner[int(o.id)] = household_id
			n += 1
	return n

## Spawn tiles on a lot.
static func spawns(lot_id: String) -> Array:
	return NeighborhoodLots.spawns_of(lot_id)
