extends RefCounted
## Cross-platform hash baseline (slow tier). Plays 3 game days from a fixed seed through the real systems and compares CoopHash.of_world()
## and the game minute with tests/baseline/coop_hash_3day.json. The file is committed, so a Linux and a Windows checkout must both
## reproduce it: a change here means the simulation changed (on purpose) or it is no longer deterministic across platforms.
## Intentional change:  run_one.gd -- coop_hash_baseline_longrun_test -- --update-baseline   (then commit the new file with a note why).
const HoodKit := preload("res://tests/hood_kit.gd")
const BASELINE := "res://tests/baseline/coop_hash_3day.json"
const SEED := 4242
const DAYS := 3

static func play() -> Dictionary:
	HoodKit.teardown()
	SimSeed.apply(SEED)
	HoodKit.new_game("classic", SEED, SEED)
	HoodKit.set_time(1, 7)
	HoodKit.run(DAYS * 1440)
	var out := {"seed": SEED, "days": DAYS, "coop_hash": CoopHash.of_world(), "minute": SimEnv.now_min()}
	HoodKit.teardown()
	return out

static func read_baseline() -> Dictionary:
	var f := FileAccess.open(BASELINE, FileAccess.READ)
	if f == null:
		return {}
	var v = JSON.parse_string(f.get_as_text())
	return v if v is Dictionary else {}

static func write_baseline(d: Dictionary) -> bool:
	var f := FileAccess.open(BASELINE, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(d, "\t", true) + "\n")
	return true

func run() -> Array:
	var got := play()
	var update := OS.get_cmdline_user_args().has("--update-baseline")
	if update:
		if not write_baseline(got):
			return ["could not write %s" % BASELINE]
		print("coop hash baseline updated: ", got)
		return []
	var want := read_baseline()
	if want.is_empty():
		return ["no baseline at %s. Create it with: run_one.gd -- coop_hash_baseline_longrun_test -- --update-baseline" % BASELINE]
	if str(want.get("coop_hash", "")) == str(got["coop_hash"]) and int(want.get("minute", -1)) == int(got["minute"]):
		return []
	return ["coop state hash after %d days drifted from the stored baseline: expected %s at minute %s, got %s at minute %s. If the simulation was changed ON PURPOSE, regenerate with: powershell tools/godot_guard.ps1 -Args \"--headless\",\"--path\",\".\",\"--script\",\"res://tests/run_one.gd\",\"--\",\"coop_hash_baseline_longrun_test\",\"--update-baseline\" and commit tests/baseline/coop_hash_3day.json with the reason. If not, something made the sim non-deterministic or platform dependent." % [DAYS, want.get("coop_hash"), str(want.get("minute")), got["coop_hash"], str(got["minute"])]]
