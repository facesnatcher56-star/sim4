extends RefCounted
## Helpers for the succession tests (task 15; no run(), so the runner skips it): a real game with one household, and quick ways to add housemates,
## townie relatives and family links.

const HoodKit := preload("res://tests/hood_kit.gd")

## Fresh game: household 1 = Mira (head, lowest id), Tobin, Wren. Nobody dies by itself.
static func new_game(world_seed: int = 1) -> Array:
	var folk: Array = HoodKit.new_game("classic", 777, world_seed)
	Players.set_player(Players.LOCAL, 1, "Test")
	Aging.set_lifespan("epic")
	return folk

static func world() -> Node:
	return HoodKit.world()

## A housemate of household 1 at the given stage.
static func housemate(nm: String, stage: String = "adult", extra_days: float = 2.0) -> Object:
	var f := Folk.create(nm, ["neat"])
	f.household_id = 1
	f.age_stage = stage
	world().add_folk(f, world().starter_spawn_tiles[0])
	Aging.set_age_days(f, float(Aging.stage_def(stage).get("from_day", 0)) + extra_days)
	return f

## A townie of the given stage; `extra_days` older than the stage start (older = bigger).
static func townie(nm: String, stage: String = "adult", extra_days: float = 2.0) -> Dictionary:
	return Story.add_townie(float(Aging.stage_def(stage).get("from_day", 0)) + extra_days, nm, ["neat"], "", 1)

static func child_of(child: int, parent: int) -> void:
	Family.link_parent(child, parent)

static func marry(a: int, b: int) -> void:
	Family.spouses[a] = b
	Family.spouses[b] = a

static func household_count(hid: int = 1) -> int:
	var n := 0
	for f in SysUtil.residents():
		if int(f.household_id) == hid:
			n += 1
	return n

static func ids_of(line: Array) -> Array:
	return line.map(func(c): return int(c["id"]))

static func teardown() -> void:
	JusticePlayer.ask_fn = Callable()
	HoodKit.teardown()
