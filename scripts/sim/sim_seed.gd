class_name SimSeed
extends RefCounted
## One master seed for every random stream of the simulation (task 17.2 / 24A.2 determinism). apply() seeds Godot's global generator (which
## still backs shuffle / pick_random / randf in older code) and each system-owned stream, so a new game started right after
## apply(s) plays out the same every time. The streams a system seeds itself on reset (Incidents, Health, Fire, markets ...) keep their own
## fixed seeds. NewGame.start calls apply() with the game's world seed; tests call it (or TestFixture.reset) before starting.

static func apply(master: int) -> void:
	seed(master)
	SysUtil.seed_rng(master)
	Genetics.seed_rng(master ^ 0x5eed1)
	Autonomy.rng = RandomNumberGenerator.new()
	Autonomy.rng.seed = master ^ 0x5eed2
	Loot.rng = RandomNumberGenerator.new()
	Loot.rng.seed = master ^ 0x5eed3
