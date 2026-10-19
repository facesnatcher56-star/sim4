extends RefCounted
## Slow tier: the real Young Family start (parents, children) over 56 game days on world seed 101, plus every townie: zero romantic
## events, romance gains, bits, interactions, affairs or pregnancies involving a minor or a relative (see romance_kit.gd).

const Kit := preload("res://tests/start_kit.gd")
const Probe = preload("res://tests/romance_kit.gd")

func run() -> Array:
	var f: Array = []
	for world_seed in [101]:
		Kit.new_game("family", "normal", {}, -1, {"world_seed": world_seed})
		var probe = Probe.new()
		probe.start()
		Careers.auto_accept_offers = false
		for hour in _days() * 24:
			Kit.run(60)
			probe.scan(Kit.world().all_folk())
		print("  seed %d: %d romantic runs, %d romance events, %d townies, %d violations" % [world_seed, probe.romantic_runs, probe.events_seen, Story.townies.size(), probe.violations.size()])
		for v in probe.violations.slice(0, 8):
			f.append("seed %d forbidden romance: %s" % [world_seed, str(v)])
		Kit.teardown()
	return f

## 56 days (about 10 s of wall time per game day); `--days=N` after `--` shortens it for a quick look.
func _days() -> int:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--days="):
			return int(str(a).substr(7))
	return 56
